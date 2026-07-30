package controller

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"sync"
	"sync/atomic"
	gotime "time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/config"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/viper"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
)

// PushController controls all push related operations
type PushController struct {
	PushRepo     *repo.PushTokenRepository
	TaskLockRepo *repo.TaskLockRepository
	HostName     string
	fcm          *fcmClient
}

type PushToken struct {
	UserID         int64
	FCMToken       *string
	APNSToken      *string
	CreatedAt      int64
	UpdatedAt      int64
	LastNotifiedAt int64
}

// Interval before which the last push was sent
const pushIntervalInMinutes = 60

// Max number of devices to notify in a single run.
const concurrentPushesInOneShot = 500

const fcmSendConcurrency = 10

const taskLockName = "fcm-push-lock"

const taskLockDurationInMinutes = 5

// As proposed by https://firebase.google.com/docs/cloud-messaging/manage-tokens#ensuring-registration-token-freshness
const tokenExpiryDurationInDays = 61

const fcmSendScope = "https://www.googleapis.com/auth/firebase.messaging"

const fcmSendTimeout = 30 * gotime.Second

func NewPushController(pushRepo *repo.PushTokenRepository, taskLockRepo *repo.TaskLockRepository, hostName string) *PushController {
	client, err := newFCMClient()
	if err != nil {
		log.Error(fmt.Errorf("error creating FCM client: %v", err))
	}
	return &PushController{PushRepo: pushRepo, TaskLockRepo: taskLockRepo, HostName: hostName, fcm: client}
}

// fcmClient sends pushes via the FCM HTTP v1 API directly. We avoid the Firebase
// Admin SDK because it pulls in the entire google.golang.org/api + Firestore +
// OpenTelemetry tree just to send a push.
type fcmClient struct {
	httpClient *http.Client
	projectID  string
}

func newFCMClient() (*fcmClient, error) {
	credentialsFile, err := config.CredentialFilePath("fcm-service-account.json")
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if credentialsFile == "" {
		// Can happen when running locally
		return nil, nil
	}
	data, err := os.ReadFile(credentialsFile)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	creds, err := google.CredentialsFromJSONWithType(context.Background(), data, google.ServiceAccount, fcmSendScope)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	client := oauth2.NewClient(context.Background(), creds.TokenSource)
	client.Timeout = fcmSendTimeout
	return &fcmClient{
		httpClient: client,
		projectID:  creds.ProjectID,
	}, nil
}

func (c *PushController) AddToken(userID int64, token ente.PushTokenRequest) error {
	return stacktrace.Propagate(c.PushRepo.AddToken(userID, token), "")
}

func (c *PushController) RemoveTokensForUser(userID int64) error {
	return stacktrace.Propagate(c.PushRepo.RemoveTokensForUser(userID), "")
}

func (c *PushController) SendPushes() {
	lockStatus, err := c.TaskLockRepo.AcquireLock(taskLockName,
		time.MicrosecondsAfterMinutes(taskLockDurationInMinutes), c.HostName)
	if err != nil {
		log.Error("Unable to acquire lock to send pushes", err)
		return
	}
	if !lockStatus {
		log.Info("Skipping sending pushes since there is an existing lock to send pushes")
		return
	}
	defer c.releaseTaskLock()

	tokens, err := c.PushRepo.GetTokensToBeNotified(time.MicrosecondsBeforeMinutes(pushIntervalInMinutes),
		concurrentPushesInOneShot)
	if err != nil {
		log.Error(fmt.Errorf("error fetching tokens to be notified: %v", err))
		return
	}

	err = c.sendFCMPushes(tokens, map[string]string{"action": "sync"})
	if err != nil {
		log.Error(fmt.Errorf("error sending pushes: %v", err))
		return
	}

	c.updateLastNotificationTime(tokens)
}

func (c *PushController) ClearExpiredTokens() {
	err := c.PushRepo.RemoveTokensOlderThan(time.NDaysFromNow(-1 * tokenExpiryDurationInDays))
	if err != nil {
		log.Errorf("Error while removing older tokens %s", err)
	} else {
		log.Info("Cleared expired FCM tokens")
	}
}

func (c *PushController) releaseTaskLock() {
	err := c.TaskLockRepo.ReleaseLock(taskLockName)
	if err != nil {
		log.Errorf("Error while releasing lock %s", err)
	}
}

func (c *PushController) updateLastNotificationTime(pushTokens []ente.PushToken) {
	err := c.PushRepo.SetLastNotificationTimeToNow(pushTokens)
	if err != nil {
		log.Error(fmt.Errorf("error updating last notified at times: %v", err))
	}
}

func (c *PushController) sendFCMPushes(pushTokens []ente.PushToken, payload map[string]string) error {
	silent := viper.GetBool("internal.silent")
	if silent || c.fcm == nil {
		if len(pushTokens) > 0 {
			log.Info("Skipping sending pushes to " + strconv.Itoa(len(pushTokens)) + " devices")
		}
		return nil
	}
	if len(pushTokens) == 0 {
		return nil
	}

	log.Info("Sending pushes to " + strconv.Itoa(len(pushTokens)) + " devices")
	var successCount, failureCount int64
	var lastErr atomic.Value
	var unregisteredMu sync.Mutex
	var unregisteredTokens []string
	var wg sync.WaitGroup
	sem := make(chan struct{}, fcmSendConcurrency)
	for _, pushToken := range pushTokens {
		wg.Add(1)
		sem <- struct{}{}
		go func(token string) {
			defer wg.Done()
			defer func() { <-sem }()
			if err := c.fcm.send(context.Background(), token, payload); err != nil {
				atomic.AddInt64(&failureCount, 1)
				lastErr.Store(err.Error())
				if errors.Is(err, errUnregisteredToken) {
					unregisteredMu.Lock()
					unregisteredTokens = append(unregisteredTokens, token)
					unregisteredMu.Unlock()
				}
			} else {
				atomic.AddInt64(&successCount, 1)
			}
		}(pushToken.FCMToken)
	}
	wg.Wait()

	if successCount == 0 && failureCount > 0 {
		msg, _ := lastErr.Load().(string)
		log.Error("Failed to send any pushes to " + strconv.FormatInt(failureCount, 10) +
			" devices; last error: " + msg)
	} else {
		log.Info("Send push result: success count: " + strconv.FormatInt(successCount, 10) +
			", failure count: " + strconv.FormatInt(failureCount, 10))
	}

	c.pruneTokens(unregisteredTokens)
	return nil
}

func (c *PushController) pruneTokens(fcmTokens []string) {
	if len(fcmTokens) == 0 {
		return
	}
	if err := c.PushRepo.RemoveTokensByFCM(fcmTokens); err != nil {
		log.Error(fmt.Errorf("error pruning %d unregistered FCM tokens: %w", len(fcmTokens), err))
		return
	}
	log.Info("Pruned " + strconv.Itoa(len(fcmTokens)) + " unregistered FCM tokens")
}

func (c *fcmClient) send(ctx context.Context, token string, data map[string]string) error {
	body, err := json.Marshal(map[string]any{
		"message": map[string]any{
			"token":   token,
			"data":    data,
			"android": map[string]any{"priority": "high"},
			"apns": map[string]any{
				"headers": map[string]string{
					"apns-push-type": "background",
					"apns-priority":  "5",
					"apns-topic":     "io.ente.frame",
				},
				"payload": map[string]any{"aps": map[string]any{"content-available": 1}},
			},
		},
	})
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	url := fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", c.projectID)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		if fcmErrorCode(b) == "UNREGISTERED" {
			return fmt.Errorf("%w (status %d)", errUnregisteredToken, resp.StatusCode)
		}
		return fmt.Errorf("status %d: %s", resp.StatusCode, string(b))
	}
	return nil
}

var errUnregisteredToken = errors.New("fcm: unregistered token")

func fcmErrorCode(body []byte) string {
	var e struct {
		Error struct {
			Details []struct {
				ErrorCode string `json:"errorCode"`
			} `json:"details"`
		} `json:"error"`
	}
	if json.Unmarshal(body, &e) != nil {
		return ""
	}
	for _, d := range e.Error.Details {
		if d.ErrorCode != "" {
			return d.ErrorCode
		}
	}
	return ""
}
