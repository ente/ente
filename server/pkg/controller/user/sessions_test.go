package user

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/controller/authsession"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
	"github.com/patrickmn/go-cache"
	"github.com/stretchr/testify/require"
)

func TestSessionIdentifiers(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "sessions@example.com", CreationTime: 1})
	userAuthRepo := &repo.UserAuthRepository{DB: db}
	authCache := cache.New(time.Minute, time.Minute)
	controller := &UserController{UserAuthRepo: userAuthRepo, Cache: authCache}
	currentToken := "current-session-token"
	otherToken := "other-session-token"
	legacyToken := "legacy-session-token"
	for _, token := range []string{currentToken, otherToken, legacyToken} {
		require.NoError(t, userAuthRepo.AddToken(userID, ente.Photos, token, "127.0.0.1", "test"))
	}

	gin.SetMode(gin.TestMode)
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	ctx.Request = httptest.NewRequest("GET", "/users/sessions", nil)
	ctx.Request.Header.Set("X-Auth-Token", currentToken)
	ctx.Request.Header.Set("X-Client-Package", "io.ente.photos")
	sessions, err := controller.GetActiveSessions(ctx, userID)
	require.NoError(t, err)
	require.Len(t, sessions, 3)

	currentHash := auth.HashToken(currentToken)
	otherHash := auth.HashToken(otherToken)
	legacyHash := auth.HashToken(legacyToken)
	currentIdentifier := encodeSessionTokenHash(currentHash[:])
	otherIdentifier := encodeSessionTokenHash(otherHash[:])
	legacyIdentifier := encodeSessionTokenHash(legacyHash[:])
	identifiers := make(map[string]bool)
	currentCount := 0
	for i := range sessions {
		identifiers[sessions[i].Token] = true
		if sessions[i].IsCurrent {
			currentCount++
			require.Equal(t, currentIdentifier, sessions[i].Token)
		}
	}
	require.Equal(t, 1, currentCount)
	require.Equal(t, map[string]bool{
		currentIdentifier: true,
		otherIdentifier:   true,
		legacyIdentifier:  true,
	}, identifiers)
	response, err := json.Marshal(sessions)
	require.NoError(t, err)
	require.NotContains(t, string(response), currentToken)
	require.NotContains(t, string(response), otherToken)
	require.NotContains(t, string(response), legacyToken)

	_, _, _, err = authsession.Authenticate(userAuthRepo, authCache, currentHash[:], ente.Photos)
	require.NoError(t, err)
	_, _, _, err = authsession.Authenticate(userAuthRepo, authCache, otherHash[:], ente.Photos)
	require.NoError(t, err)
	identifierHash := auth.HashToken(otherIdentifier)
	_, _, _, err = authsession.Authenticate(userAuthRepo, authCache, identifierHash[:], ente.Photos)
	require.ErrorIs(t, err, sql.ErrNoRows)

	for _, identifier := range []string{currentToken, currentIdentifier} {
		err = controller.TerminateSessionByIdentifier(userID, currentToken, identifier)
		var apiErr *ente.ApiError
		require.ErrorAs(t, err, &apiErr)
		require.Equal(t, http.StatusBadRequest, apiErr.HttpStatusCode)
	}
	_, _, _, err = authsession.Authenticate(userAuthRepo, authCache, currentHash[:], ente.Photos)
	require.NoError(t, err)

	require.NoError(t, controller.TerminateSessionByIdentifier(userID, currentToken, otherIdentifier))
	_, _, _, err = authsession.Authenticate(userAuthRepo, authCache, otherHash[:], ente.Photos)
	require.ErrorIs(t, err, sql.ErrNoRows)
	require.NoError(t, controller.TerminateSessionByIdentifier(userID, currentToken, legacyToken))
	_, _, _, err = authsession.Authenticate(userAuthRepo, authCache, legacyHash[:], ente.Photos)
	require.ErrorIs(t, err, sql.ErrNoRows)
}
