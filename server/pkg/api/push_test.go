package api

import (
	"encoding/base64"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestPushRegistrationBindsRequestSession(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	router := gin.New()
	handler := PushHandler{PushController: &controller.PushController{PushRepo: &repo.PushTokenRepository{DB: db}}}
	router.POST("/push/token", handler.AddToken)
	for _, id := range []int64{1, 2} {
		testutil.InsertUser(t, db, testutil.UserFixture{UserID: id, Email: fmt.Sprintf("user%d@example.com", id), CreationTime: 1})
		session := fmt.Sprintf("session-%d", id)
		require.NoError(t, (&repo.UserAuthRepository{DB: db}).AddToken(id, ente.Photos, session, "", ""))
		body := fmt.Sprintf(`{"fcmToken":"device", "apnsToken":"apns-%d", "sessionTokenHash":"%s"}`, id, base64.StdEncoding.EncodeToString([]byte("untrusted-session")))
		request := httptest.NewRequest(http.MethodPost, "/push/token", strings.NewReader(body))
		request.Header.Set("Content-Type", "application/json")
		request.Header.Set("X-Auth-User-ID", fmt.Sprint(id))
		request.Header.Set("X-Auth-Token", session)
		response := httptest.NewRecorder()
		router.ServeHTTP(response, request)
		require.Equal(t, http.StatusOK, response.Code)
		var owner int64
		var apns string
		require.NoError(t, db.QueryRow(`SELECT user_id, apns_token FROM push_tokens WHERE fcm_token = 'device'`).Scan(&owner, &apns))
		require.Equal(t, id, owner)
		require.Equal(t, fmt.Sprintf("apns-%d", id), apns)
	}
	oldHash := auth.HashToken("session-1")
	_, err := (&repo.UserAuthRepository{DB: db}).RemoveTokenByHash(1, oldHash[:])
	require.NoError(t, err)
	for _, session := range []string{"session-1", "session-2"} {
		request := httptest.NewRequest(http.MethodPost, "/push/token", strings.NewReader(`{"fcmToken":"device"}`))
		request.Header.Set("Content-Type", "application/json")
		request.Header.Set("X-Auth-User-ID", "1")
		request.Header.Set("X-Auth-Token", session)
		response := httptest.NewRecorder()
		router.ServeHTTP(response, request)
		require.Equal(t, http.StatusUnauthorized, response.Code)
		var owner int64
		require.NoError(t, db.QueryRow(`SELECT user_id FROM push_tokens WHERE fcm_token = 'device'`).Scan(&owner))
		require.Equal(t, int64(2), owner)
	}
	var hash []byte
	require.NoError(t, db.QueryRow(`SELECT session_token_hash FROM push_tokens WHERE fcm_token = 'device'`).Scan(&hash))
	expected := auth.HashToken("session-2")
	require.Equal(t, expected[:], hash)
}

func TestPushPlatformRegistration(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "push@example.com", CreationTime: 1})
	require.NoError(t, (&repo.UserAuthRepository{DB: db}).AddToken(1, ente.Photos, "session", "", ""))
	router := gin.New()
	handler := PushHandler{PushController: &controller.PushController{PushRepo: &repo.PushTokenRepository{DB: db}}}
	router.POST("/push/token", handler.AddToken)
	for _, tc := range []struct {
		name, fields, platform string
		status                 int
	}{
		{"old client", "", "ios", http.StatusOK},
		{"android", `,"platform":"android","apnsToken":null`, "android", http.StatusOK},
		{"ios", `,"platform":"ios"`, "ios", http.StatusOK},
		{"invalid platform", `,"platform":"web"`, "ios", http.StatusBadRequest},
		{"null platform", `,"platform":null`, "ios", http.StatusBadRequest},
	} {
		t.Run(tc.name, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodPost, "/push/token", strings.NewReader(`{"fcmToken":"device"`+tc.fields+`}`))
			request.Header.Set("Content-Type", "application/json")
			request.Header.Set("X-Auth-User-ID", "1")
			request.Header.Set("X-Auth-Token", "session")
			response := httptest.NewRecorder()
			router.ServeHTTP(response, request)
			require.Equal(t, tc.status, response.Code, response.Body.String())
			var platform string
			require.NoError(t, db.QueryRow(`SELECT platform FROM push_tokens WHERE fcm_token='device'`).Scan(&platform))
			require.Equal(t, tc.platform, platform)
		})
	}
}
