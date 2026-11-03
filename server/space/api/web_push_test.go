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
	auth := base64.URLEncoding.EncodeToString(make([]byte, 16))
	payload, err := json.Marshal(map[string]any{
		"endpoint": "https://fcm.googleapis.com/wp/subscription",
		"keys": map[string]string{
			"p256dh": base64.RawURLEncoding.EncodeToString(privateKey.PublicKey().Bytes()),
			"auth":   auth,
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

	sessionToken = "new-space-web-push-session"
	sessionHash = sha256.Sum256([]byte(sessionToken))
	require.NoError(t, repos.Sessions.CreateBrowserSession(context.Background(), sessionHash[:], userID, "wrap-key", timeutil.NDaysFromNow(1)))
	for _, testCase := range []struct {
		auth   string
		status int
	}{
		{base64.RawURLEncoding.EncodeToString(bytes.Repeat([]byte{1}, 16)), http.StatusConflict},
		{base64.RawURLEncoding.EncodeToString(make([]byte, 16)), http.StatusOK},
		{auth, http.StatusOK},
	} {
		retryPayload := bytes.ReplaceAll(payload, []byte(auth), []byte(testCase.auth))
		retryRequest := httptest.NewRequest(http.MethodPut, "/account/space/push/subscription", bytes.NewReader(retryPayload))
		retryRequest.Header.Set(controller.SpaceBrowserSessionTokenHeader, sessionToken)
		retryRequest.Header.Set("Content-Type", "application/json")
		retryRecorder := httptest.NewRecorder()
		privateRouter.ServeHTTP(retryRecorder, retryRequest)
		require.Equal(t, testCase.status, retryRecorder.Code)
		if testCase.status == http.StatusOK {
			require.JSONEq(t, subscriptionRecorder.Body.String(), retryRecorder.Body.String())
		}
	}
	require.NoError(t, repos.WebPush.DB.QueryRow(`
		SELECT COUNT(*)
		FROM space_web_push_subscriptions
		WHERE session_token_hash = $1
	`, sessionHash[:]).Scan(&count))
	require.Equal(t, 1, count)

	unsubscriptionPayload, err := json.Marshal(map[string]string{
		"endpoint": "https://fcm.googleapis.com/wp/subscription",
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

func TestSpaceLinkWebPushDeletionRequiresSubscriptionAuth(t *testing.T) {
	handlers, repos, userID := setupSpaceSessionAPITest(t, nil)
	ctx := context.Background()
	space, err := testCreateSpace(ctx, repos, userID, "space_push_link", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)
	linkAuth := bytes.Repeat([]byte{1}, 32)
	linkAuthHash := sha256.Sum256(linkAuth)
	link, err := repos.Links.Create(ctx, space.SpaceID, linkAuthHash[:], bytes.Repeat([]byte{2}, 16), 67108864, 2, space.CurrentVersion, []byte("encrypted-space-key"), []byte("encrypted-access-key"))
	require.NoError(t, err)
	privateKey, err := ecdh.P256().GenerateKey(rand.Reader)
	require.NoError(t, err)
	p256dh := base64.RawURLEncoding.EncodeToString(privateKey.PublicKey().Bytes())
	auth := base64.RawURLEncoding.EncodeToString(make([]byte, 16))
	paddedAuth := base64.URLEncoding.EncodeToString(make([]byte, 16))
	wrongAuth := base64.RawURLEncoding.EncodeToString(bytes.Repeat([]byte{1}, 16))
	endpoint := "https://fcm.googleapis.com/wp/link-subscription"
	targetID, err := repos.WebPush.UpsertLinkSubscription(ctx, link.LinkID, endpoint, p256dh, paddedAuth)
	require.NoError(t, err)

	router := gin.New()
	path := "/space/public/by-slug/:spaceSlug/link/push/subscription"
	router.PUT(path, handlers.UpsertSpaceLinkWebPushSubscription)
	router.DELETE(path, handlers.DeleteSpaceLinkWebPushSubscription)
	url := "/space/public/by-slug/" + space.SpaceSlug + "/link/push/subscription"
	for _, testCase := range []struct {
		auth   string
		status int
	}{
		{"", http.StatusBadRequest},
		{wrongAuth, http.StatusOK},
	} {
		payload, err := json.Marshal(map[string]string{"endpoint": endpoint, "auth": testCase.auth})
		require.NoError(t, err)
		request := httptest.NewRequest(http.MethodDelete, url, bytes.NewReader(payload))
		request.Header.Set(controller.SpaceLinkAuthHeader, base64.StdEncoding.EncodeToString(linkAuth))
		request.Header.Set("Content-Type", "application/json")
		recorder := httptest.NewRecorder()
		router.ServeHTTP(recorder, request)
		require.Equal(t, testCase.status, recorder.Code, recorder.Body.String())
		var storedP256dh, storedAuth string
		require.NoError(t, repos.WebPush.DB.QueryRow(`
			SELECT p256dh, auth FROM space_web_push_subscriptions WHERE target_id = $1
		`, targetID).Scan(&storedP256dh, &storedAuth))
		require.Equal(t, p256dh, storedP256dh)
		require.Equal(t, paddedAuth, storedAuth)
	}
	for _, testCase := range []struct {
		auth   string
		status int
	}{
		{wrongAuth, http.StatusConflict},
		{auth, http.StatusOK},
		{paddedAuth, http.StatusOK},
	} {
		payload, err := json.Marshal(map[string]any{
			"endpoint": endpoint,
			"keys":     map[string]string{"p256dh": p256dh, "auth": testCase.auth},
		})
		require.NoError(t, err)
		request := httptest.NewRequest(http.MethodPut, url, bytes.NewReader(payload))
		request.Header.Set(controller.SpaceLinkAuthHeader, base64.StdEncoding.EncodeToString(linkAuth))
		request.Header.Set("Content-Type", "application/json")
		recorder := httptest.NewRecorder()
		router.ServeHTTP(recorder, request)
		require.Equal(t, testCase.status, recorder.Code, recorder.Body.String())
		if testCase.status == http.StatusOK {
			require.JSONEq(t, `{"targetId":"`+targetID+`"}`, recorder.Body.String())
		}
	}
	for range 2 {
		payload, err := json.Marshal(map[string]string{"endpoint": endpoint, "auth": auth})
		require.NoError(t, err)
		request := httptest.NewRequest(http.MethodDelete, url, bytes.NewReader(payload))
		request.Header.Set(controller.SpaceLinkAuthHeader, base64.StdEncoding.EncodeToString(linkAuth))
		request.Header.Set("Content-Type", "application/json")
		recorder := httptest.NewRecorder()
		router.ServeHTTP(recorder, request)
		require.Equal(t, http.StatusOK, recorder.Code, recorder.Body.String())
		var count int
		require.NoError(t, repos.WebPush.DB.QueryRow(`
			SELECT COUNT(*) FROM space_web_push_subscriptions WHERE target_id = $1
		`, targetID).Scan(&count))
		require.Zero(t, count)
	}
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
