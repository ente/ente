package api

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestAdminFactorChangesRequireFreshToken(t *testing.T) {
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	adminID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "admin@example.com", CreationTime: 1})

	for _, token := range []struct {
		value     string
		createdAt int64
	}{
		{"old-token", time.Now().Add(-11 * time.Minute).UnixMicro()},
		{"fresh-token", time.Now().UnixMicro()},
	} {
		hash := auth.HashToken(token.value)
		_, err := db.Exec(`INSERT INTO tokens(user_id, token_hash, creation_time, app) VALUES($1, $2, $3, $4)`,
			adminID, hash[:], token.createdAt, ente.Photos)
		require.NoError(t, err)
	}

	h := &AdminHandler{UserAuthRepo: &repo.UserAuthRepository{DB: db}}
	for _, route := range []struct {
		path    string
		handler gin.HandlerFunc
		body    string
	}{
		{"/admin/user/disable-passkeys", h.RemovePasskeys, `{"userID":2}`},
		{"/admin/user/update-email-mfa", h.UpdateEmailMFA, `{"userID":2,"emailMFA":false}`},
	} {
		t.Run(route.path, func(t *testing.T) {
			router := gin.New()
			router.POST(route.path, route.handler)

			request := httptest.NewRequest(http.MethodPost, route.path, strings.NewReader(route.body))
			request.Header.Set("X-Auth-Token", "old-token")
			request.Header.Set("Content-Type", "application/json")
			response := httptest.NewRecorder()
			router.ServeHTTP(response, request)
			require.Equal(t, http.StatusBadRequest, response.Code)
			require.Contains(t, response.Body.String(), "Token is too old")

			request = httptest.NewRequest(http.MethodPost, route.path, strings.NewReader("invalid JSON"))
			request.Header.Set("X-Auth-Token", "fresh-token")
			request.Header.Set("Content-Type", "application/json")
			response = httptest.NewRecorder()
			router.ServeHTTP(response, request)
			require.Equal(t, http.StatusBadRequest, response.Code)
			require.NotContains(t, response.Body.String(), "Token is too old")
		})
	}
}
