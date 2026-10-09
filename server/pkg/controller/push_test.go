package controller

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/auth"
	log "github.com/sirupsen/logrus"
	logtest "github.com/sirupsen/logrus/hooks/test"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func jsonResponse(status int, body string) *http.Response {
	return &http.Response{
		StatusCode: status,
		Body:       io.NopCloser(strings.NewReader(body)),
		Header:     make(http.Header),
	}
}

type wireMsg struct {
	Message struct {
		Token   string            `json:"token"`
		Data    map[string]string `json:"data"`
		Android struct {
			Priority string `json:"priority"`
		} `json:"android"`
		APNS struct {
			Headers map[string]string `json:"headers"`
			Payload struct {
				Aps struct {
					ContentAvailable int `json:"content-available"`
				} `json:"aps"`
			} `json:"payload"`
		} `json:"apns"`
	} `json:"message"`
}

func TestFCMSendBuildsV1Request(t *testing.T) {
	var captured *http.Request
	var body []byte
	c := &fcmClient{
		projectID: "proj-123",
		httpClient: &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
			captured = r
			body, _ = io.ReadAll(r.Body)
			return jsonResponse(http.StatusOK, "{}"), nil
		})},
	}

	err := c.send(context.Background(), "device-token-abc", map[string]string{"action": "sync"})
	require.NoError(t, err)

	require.Equal(t, http.MethodPost, captured.Method)
	require.Equal(t, "https://fcm.googleapis.com/v1/projects/proj-123/messages:send", captured.URL.String())
	require.Equal(t, "application/json", captured.Header.Get("Content-Type"))

	var msg wireMsg
	require.NoError(t, json.Unmarshal(body, &msg))
	require.Equal(t, "device-token-abc", msg.Message.Token)
	require.Equal(t, map[string]string{"action": "sync"}, msg.Message.Data)
	require.Equal(t, "high", msg.Message.Android.Priority)
	require.Equal(t, map[string]string{
		"apns-push-type": "background",
		"apns-priority":  "5",
		"apns-topic":     "io.ente.frame",
	}, msg.Message.APNS.Headers)
	require.Equal(t, 1, msg.Message.APNS.Payload.Aps.ContentAvailable)
}

func TestFCMSendNon200ReturnsError(t *testing.T) {
	c := &fcmClient{
		projectID: "p",
		httpClient: &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
			return jsonResponse(http.StatusNotFound, `{"error":"not found"}`), nil
		})},
	}

	err := c.send(context.Background(), "tok", map[string]string{"action": "sync"})
	require.Error(t, err)
	require.Contains(t, err.Error(), "404")
}

func TestSendFCMPushesCountsResults(t *testing.T) {
	hook := captureLogs(t)
	var requests int64
	pc := &PushController{fcm: &fcmClient{
		projectID: "p",
		httpClient: &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
			atomic.AddInt64(&requests, 1)
			b, _ := io.ReadAll(r.Body)
			var m wireMsg
			_ = json.Unmarshal(b, &m)
			if strings.HasPrefix(m.Message.Token, "bad") {
				return jsonResponse(http.StatusBadRequest, `{"error":"bad"}`), nil
			}
			return jsonResponse(http.StatusOK, "{}"), nil
		})},
	}}

	tokens := []ente.PushToken{{FCMToken: "good-1"}, {FCMToken: "good-2"}, {FCMToken: "bad-3"}}
	require.NoError(t, pc.sendFCMPushes(tokens, map[string]string{"action": "sync"}))

	require.Equal(t, int64(3), atomic.LoadInt64(&requests))
	require.True(t, hasLog(hook, log.InfoLevel, "success count: 2, failure count: 1"))
	require.False(t, hasLog(hook, log.ErrorLevel, "Failed to send any pushes"))
}

func TestSendFCMPushesTotalFailureLogsError(t *testing.T) {
	hook := captureLogs(t)
	pc := &PushController{fcm: &fcmClient{
		projectID: "p",
		httpClient: &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
			return jsonResponse(http.StatusBadRequest, `{"error":"bad"}`), nil
		})},
	}}

	tokens := []ente.PushToken{{FCMToken: "a"}, {FCMToken: "b"}}
	require.NoError(t, pc.sendFCMPushes(tokens, map[string]string{"action": "sync"}))

	require.True(t, hasLog(hook, log.ErrorLevel, "Failed to send any pushes to 2 devices"))
}

const fcmUnregisteredBody = `{"error":{"code":404,"status":"NOT_FOUND","message":"Requested entity was not found.","details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"UNREGISTERED"}]}}`

const fcmInvalidArgumentBody = `{"error":{"code":400,"status":"INVALID_ARGUMENT","message":"The registration token is not a valid FCM registration token","details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"INVALID_ARGUMENT"},{"@type":"type.googleapis.com/google.rpc.BadRequest","fieldViolations":[{"field":"message.token","description":"The registration token is not a valid FCM registration token"}]}]}}`

func TestFCMSendClassifiesUnregistered(t *testing.T) {
	c := &fcmClient{
		projectID: "p",
		httpClient: &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
			return jsonResponse(http.StatusNotFound, fcmUnregisteredBody), nil
		})},
	}
	err := c.send(context.Background(), "tok", map[string]string{"action": "sync"})
	require.Error(t, err)
	require.True(t, errors.Is(err, errUnregisteredToken))
}

func TestFCMSendDoesNotClassifyInvalidArgumentAsUnregistered(t *testing.T) {
	c := &fcmClient{
		projectID: "p",
		httpClient: &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
			return jsonResponse(http.StatusBadRequest, fcmInvalidArgumentBody), nil
		})},
	}
	err := c.send(context.Background(), "tok", map[string]string{"action": "sync"})
	require.Error(t, err)
	require.False(t, errors.Is(err, errUnregisteredToken))
}

func TestAlbumShareSendsOnlyAndroidSync(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "internal@example.com", CreationTime: 1})
	_, err := db.Exec(`INSERT INTO remote_store(user_id,key_name,key_value) VALUES(1,'internalUser','true')`)
	require.NoError(t, err)
	require.NoError(t, (&repo.UserAuthRepository{DB: db}).AddToken(1, ente.Photos, "session", "", ""))
	hash := auth.HashToken("session")
	controller := &PushController{PushRepo: &repo.PushTokenRepository{DB: db}}
	for _, platform := range []string{"ios", "android"} {
		require.NoError(t, controller.AddToken(1, hash[:], ente.PushTokenRequest{
			FCMToken: platform + "-device", Platform: &platform,
		}))
	}
	var messages []map[string]any
	controller.fcm = &fcmClient{projectID: "test-project", httpClient: &http.Client{Transport: roundTripFunc(func(request *http.Request) (*http.Response, error) {
		require.NoError(t, request.Context().Err())
		var envelope struct {
			Message map[string]any `json:"message"`
		}
		require.NoError(t, json.NewDecoder(request.Body).Decode(&envelope))
		messages = append(messages, envelope.Message)
		return jsonResponse(http.StatusOK, "{}"), nil
	})}}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	controller.NotifyAlbumShare(ctx, []int64{1})
	require.Equal(t, []map[string]any{{
		"token":   "android-device",
		"data":    map[string]any{"action": "sync"},
		"android": map[string]any{"priority": "high", "ttl": "86400s"},
	}}, messages)
}

func TestAlbumSharePrunesOnlyUnregisteredTokens(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "internal@example.com", CreationTime: 1})
	_, err := db.Exec(`INSERT INTO remote_store(user_id,key_name,key_value) VALUES(1,'internalUser','true')`)
	require.NoError(t, err)
	require.NoError(t, (&repo.UserAuthRepository{DB: db}).AddToken(1, ente.Photos, "session", "", ""))
	hash := auth.HashToken("session")
	platform := "android"
	controller := &PushController{PushRepo: &repo.PushTokenRepository{DB: db}}
	responses := map[string]struct {
		status int
		body   string
	}{
		"active":           {http.StatusOK, "{}"},
		"unregistered":     {http.StatusNotFound, fcmUnregisteredBody},
		"unavailable":      {http.StatusServiceUnavailable, "unavailable"},
		"unauthorized":     {http.StatusUnauthorized, "unauthorized"},
		"invalid-argument": {http.StatusBadRequest, fcmInvalidArgumentBody},
	}
	for token := range responses {
		require.NoError(t, controller.AddToken(1, hash[:], ente.PushTokenRequest{
			FCMToken: token, Platform: &platform,
		}))
	}
	var attempted []string
	controller.fcm = &fcmClient{projectID: "test-project", httpClient: &http.Client{Transport: roundTripFunc(func(request *http.Request) (*http.Response, error) {
		var message wireMsg
		require.NoError(t, json.NewDecoder(request.Body).Decode(&message))
		attempted = append(attempted, message.Message.Token)
		response := responses[message.Message.Token]
		return jsonResponse(response.status, response.body), nil
	})}}
	controller.NotifyAlbumShare(context.Background(), []int64{1})
	require.ElementsMatch(t, []string{"active", "unregistered", "unavailable", "unauthorized", "invalid-argument"}, attempted)
	var unregisteredExists bool
	require.NoError(t, db.QueryRow(`SELECT EXISTS(SELECT 1 FROM push_tokens WHERE fcm_token='unregistered')`).Scan(&unregisteredExists))
	require.False(t, unregisteredExists)
	attempted = nil
	controller.NotifyAlbumShare(context.Background(), []int64{1})
	require.ElementsMatch(t, []string{"active", "unavailable", "unauthorized", "invalid-argument"}, attempted)
}

func TestAlbumShareHonorsSilentMode(t *testing.T) {
	previous := viper.GetBool("internal.silent")
	viper.Set("internal.silent", true)
	t.Cleanup(func() { viper.Set("internal.silent", previous) })
	controller := &PushController{fcm: &fcmClient{}}
	controller.NotifyAlbumShare(context.Background(), []int64{1})
}

func captureLogs(t *testing.T) *logtest.Hook {
	t.Helper()
	logger := log.StandardLogger()
	origHooks := logger.ReplaceHooks(make(log.LevelHooks))
	origOut := logger.Out
	logger.SetOutput(io.Discard)
	hook := logtest.NewGlobal()
	t.Cleanup(func() {
		logger.ReplaceHooks(origHooks)
		logger.SetOutput(origOut)
		hook.Reset()
	})
	return hook
}

func hasLog(hook *logtest.Hook, level log.Level, substr string) bool {
	for _, e := range hook.AllEntries() {
		if e.Level == level && strings.Contains(e.Message, substr) {
			return true
		}
	}
	return false
}
