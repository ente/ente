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
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
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

func TestAlbumSharePushOnlyInternalIOSRecipients(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	silent := viper.GetBool("internal.silent")
	t.Cleanup(func() { testutil.ResetTables(t, db); viper.Set("internal.silent", silent) })
	for _, u := range []testutil.UserFixture{{UserID: 1, Email: "owner@example.com", CreationTime: 1}, {UserID: 2, Email: "recipient@example.com", CreationTime: 1}} {
		testutil.InsertUser(t, db, u)
	}
	r := &repo.PushTokenRepository{DB: db}
	require.NoError(t, r.AddToken(2, ente.PushTokenRequest{FCMToken: "ios-device", APNSToken: "apns-device"}))
	require.NoError(t, r.AddToken(2, ente.PushTokenRequest{FCMToken: "android-device"}))
	_, err := db.Exec(`INSERT INTO push_tokens (user_id, fcm_token, apns_token) VALUES (2, 'empty-apns', '')`)
	require.NoError(t, err)
	var messages []map[string]any
	c := &PushController{PushRepo: r, fcm: &fcmClient{projectID: "test", httpClient: &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
		var body struct{ Message map[string]any }
		require.NoError(t, json.NewDecoder(req.Body).Decode(&body))
		messages = append(messages, body.Message)
		return jsonResponse(http.StatusOK, `{}`), nil
	})}}}
	viper.Set("internal.silent", false)
	c.NotifyAlbumShare(context.Background(), []int64{2})
	require.Empty(t, messages, "ordinary users must not receive push")
	_, err = db.Exec(`INSERT INTO remote_store (user_id, key_name, key_value) VALUES (2, 'internalUser', 'false')`)
	require.NoError(t, err)
	c.NotifyAlbumShare(context.Background(), []int64{2})
	require.Empty(t, messages, "the internal flag must be true")
	_, err = db.Exec(`UPDATE remote_store SET key_value = 'true' WHERE user_id = 2 AND key_name = 'internalUser'`)
	require.NoError(t, err)
	c.NotifyAlbumShare(context.Background(), []int64{1})
	viper.Set("internal.silent", true)
	c.NotifyAlbumShare(context.Background(), []int64{2})
	require.Empty(t, messages)
	viper.Set("internal.silent", false)
	c.NotifyAlbumShare(context.Background(), []int64{1, 2})
	require.Len(t, messages, 1)
	require.Equal(t, "ios-device", messages[0]["token"])
	require.Equal(t, map[string]any{"title": "Ente Photos", "body": "An album was shared with you"}, messages[0]["notification"])
	require.Equal(t, map[string]any{
		"headers": map[string]any{"apns-push-type": "alert", "apns-priority": "10", "apns-expiration": "0"},
		"payload": map[string]any{"aps": map[string]any{"sound": "default"}},
	}, messages[0]["apns"])
	require.Nil(t, messages[0]["android"])
	require.Nil(t, messages[0]["data"])
	require.NoError(t, r.AddToken(1, ente.PushTokenRequest{FCMToken: "ios-device", APNSToken: "apns-device"}))
	c.NotifyAlbumShare(context.Background(), []int64{2})
	require.Len(t, messages, 1, "token registered to another account must not receive the alert")
}

func TestPushTokenFollowsCurrentAccount(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	for _, id := range []int64{1, 2} {
		testutil.InsertUser(t, db, testutil.UserFixture{UserID: id, CreationTime: 1, Email: string(rune('a'+id)) + "@example.com"})
	}
	r := &repo.PushTokenRepository{DB: db}
	for _, id := range []int64{1, 2} {
		if err := r.AddToken(id, ente.PushTokenRequest{FCMToken: "test-device"}); err != nil {
			t.Fatal(err)
		}
	}
	var owner int64
	if err := db.QueryRow(`SELECT user_id FROM push_tokens WHERE fcm_token = 'test-device'`).Scan(&owner); err != nil {
		t.Fatal(err)
	}
	if owner != 2 {
		t.Fatalf("token owner = %d, want current account 2", owner)
	}
}

func TestAlbumSharePushSurvivesSlowDelivery(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	silent := viper.GetBool("internal.silent")
	t.Cleanup(func() { testutil.ResetTables(t, db); viper.Set("internal.silent", silent) })
	viper.Set("internal.silent", false)
	testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "internal@example.com", CreationTime: 1})
	_, err := db.Exec(`INSERT INTO remote_store (user_id, key_name, key_value) VALUES (1, 'internalUser', 'true')`)
	require.NoError(t, err)
	r := &repo.PushTokenRepository{DB: db}
	for _, token := range []string{"first-device", "second-device"} {
		require.NoError(t, r.AddToken(1, ente.PushTokenRequest{FCMToken: token, APNSToken: "apns"}))
	}
	delivered := 0
	done := make(chan struct{})
	c := &PushController{PushRepo: r, fcm: &fcmClient{projectID: "test", httpClient: &http.Client{
		Timeout: fcmSendTimeout,
		Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
			if delivered == 0 {
				timer := time.NewTimer(6 * time.Second)
				defer timer.Stop()
				select {
				case <-timer.C:
				case <-req.Context().Done():
					return nil, req.Context().Err()
				}
			}
			if err := req.Context().Err(); err != nil {
				return nil, err
			}
			delivered++
			if delivered == 2 {
				close(done)
			}
			return jsonResponse(http.StatusOK, `{}`), nil
		}),
	}}}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	go c.NotifyAlbumShare(ctx, []int64{1})
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Fatal("both devices should receive a push despite a slow send and a cancelled request")
	}
}
