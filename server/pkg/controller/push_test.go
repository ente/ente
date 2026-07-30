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
	log "github.com/sirupsen/logrus"
	logtest "github.com/sirupsen/logrus/hooks/test"
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

// wireMsg mirrors the FCM HTTP v1 request body so tests can assert the exact
// JSON we put on the wire.
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

func TestFCMErrorCode(t *testing.T) {
	require.Equal(t, "UNREGISTERED", fcmErrorCode([]byte(fcmUnregisteredBody)))
	require.Equal(t, "INVALID_ARGUMENT", fcmErrorCode([]byte(fcmInvalidArgumentBody)))
	require.Equal(t, "", fcmErrorCode([]byte(`{"error":"bad"}`)))
	require.Equal(t, "", fcmErrorCode([]byte("not json")))
	require.Equal(t, "", fcmErrorCode(nil))
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
