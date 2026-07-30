package api

import (
	"bytes"
	"context"
	"crypto/ecdh"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	webpush "github.com/SherClockHolmes/webpush-go"
	timeutil "github.com/ente/museum/pkg/utils/time"
	"github.com/ente/museum/space/controller"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestSpaceWebPushAccountSubscriptionAPI(t *testing.T) {
	webPushConfig, vapidPublicKey := newSpaceWebPushAPITestConfig(t)
	handlers, repos, userID := setupSpaceSessionAPITest(t, webPushConfig)
	sessionToken := "space-web-push-session"
	sessionHash := sha256.Sum256([]byte(sessionToken))
	require.NoError(t, repos.Sessions.CreateBrowserSession(context.Background(), sessionHash[:], userID, "wrap-key", timeutil.NDaysFromNow(1)))

	publicRouter := gin.New()
	publicRouter.GET("/space/push/vapid-key", handlers.GetWebPushVAPIDKey)
	keyRequest := httptest.NewRequest(http.MethodGet, "/space/push/vapid-key", nil)
	keyRecorder := httptest.NewRecorder()
	publicRouter.ServeHTTP(keyRecorder, keyRequest)
	require.Equal(t, http.StatusOK, keyRecorder.Code)
	require.JSONEq(t, `{"publicKey":"`+vapidPublicKey+`"}`, keyRecorder.Body.String())

	privateKey, err := ecdh.P256().GenerateKey(rand.Reader)
	require.NoError(t, err)
	payload, err := json.Marshal(map[string]any{
		"endpoint": "https://push.example/subscription",
		"keys": map[string]string{
			"p256dh": base64.RawURLEncoding.EncodeToString(privateKey.PublicKey().Bytes()),
			"auth":   base64.RawURLEncoding.EncodeToString(make([]byte, 16)),
		},
	})
	require.NoError(t, err)

	privateRouter := gin.New()
	privateRouter.Use(handlers.RequireSpaceBrowserSession())
	privateRouter.PUT("/account/space/push/subscription", handlers.UpsertWebPushSubscription)
	privateRouter.DELETE("/account/space/push/subscription", handlers.DeleteWebPushSubscription)
	subscriptionRequest := httptest.NewRequest(http.MethodPut, "/account/space/push/subscription", bytes.NewReader(payload))
	subscriptionRequest.Header.Set(controller.SpaceBrowserSessionTokenHeader, sessionToken)
	subscriptionRequest.Header.Set("Content-Type", "application/json")
	subscriptionRecorder := httptest.NewRecorder()
	privateRouter.ServeHTTP(subscriptionRecorder, subscriptionRequest)
	require.Equal(t, http.StatusOK, subscriptionRecorder.Code)
	require.Contains(t, subscriptionRecorder.Body.String(), `"targetId":"wpt_`)

	var count int
	require.NoError(t, repos.WebPush.DB.QueryRow(`
		SELECT COUNT(*)
		FROM space_web_push_subscriptions
		WHERE session_token_hash = $1
	`, sessionHash[:]).Scan(&count))
	require.Equal(t, 1, count)

	unsubscriptionPayload, err := json.Marshal(map[string]string{
		"endpoint": "https://push.example/subscription",
	})
	require.NoError(t, err)
	unsubscriptionRequest := httptest.NewRequest(http.MethodDelete, "/account/space/push/subscription", bytes.NewReader(unsubscriptionPayload))
	unsubscriptionRequest.Header.Set(controller.SpaceBrowserSessionTokenHeader, sessionToken)
	unsubscriptionRequest.Header.Set("Content-Type", "application/json")
	unsubscriptionRecorder := httptest.NewRecorder()
	privateRouter.ServeHTTP(unsubscriptionRecorder, unsubscriptionRequest)
	require.Equal(t, http.StatusOK, unsubscriptionRecorder.Code)
	require.NoError(t, repos.WebPush.DB.QueryRow(`
		SELECT COUNT(*)
		FROM space_web_push_subscriptions
		WHERE session_token_hash = $1
	`, sessionHash[:]).Scan(&count))
	require.Zero(t, count)
}

func TestSpaceWebPushVAPIDKeyRequiresCompleteConfig(t *testing.T) {
	handlers, _, _ := setupSpaceSessionAPITest(t, nil)

	router := gin.New()
	router.GET("/space/push/vapid-key", handlers.GetWebPushVAPIDKey)
	request := httptest.NewRequest(http.MethodGet, "/space/push/vapid-key", nil)
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, request)
	require.Equal(t, http.StatusServiceUnavailable, recorder.Code)
}

func newSpaceWebPushAPITestConfig(
	t *testing.T,
) (*controller.SpaceWebPushConfig, string) {
	t.Helper()
	privateKey, publicKey, err := webpush.GenerateVAPIDKeys()
	require.NoError(t, err)
	config := controller.NewSpaceWebPushConfig(publicKey, privateKey, "security@ente.io")
	require.NotNil(t, config)
	return config, publicKey
}
