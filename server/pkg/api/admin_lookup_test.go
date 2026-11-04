package api

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/crypto"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestAdminLookupsRequireSelfHosting(t *testing.T) {
	db := testutil.RequireTestDB(t)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	const email = "admin@example.com"
	emailHash, err := crypto.GetHash(email, testutil.HashingKey())
	require.NoError(t, err)

	h := &AdminHandler{
		UserRepo: &repo.UserRepository{
			DB:                  db,
			SecretEncryptionKey: testutil.SecretEncryptionKey(),
		},
		UserAuthRepo: &repo.UserAuthRepository{DB: db},
		HashingKey:   testutil.HashingKey(),
	}
	router := gin.New()
	router.GET("/admin/users", h.GetUsers)
	router.GET("/admin/email-hash", h.GetEmailHash)
	router.POST("/admin/emails-from-hashes", h.GetEmailsFromHashes)

	for _, tt := range []struct {
		name   string
		hosted bool
		status int
	}{
		{"self_hosted", false, http.StatusOK},
		{"hosted", true, http.StatusNotFound},
	} {
		t.Run(tt.name, func(t *testing.T) {
			testutil.ResetTables(t, db)
			adminID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 2, Email: email, CreationTime: 1})
			if tt.hosted {
				testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "first@ente.io", CreationTime: 1})
			}
			tokenHash := auth.HashToken("fresh-admin-token")
			_, err := db.Exec(`INSERT INTO tokens(user_id, token_hash, creation_time, app) VALUES($1, $2, $3, $4)`,
				adminID, tokenHash[:], time.Now().UnixMicro(), ente.Photos)
			require.NoError(t, err)

			for _, route := range []struct {
				method, target, body, want string
			}{
				{http.MethodGet, "/admin/users?sinceTime=0", "", email},
				{http.MethodGet, "/admin/email-hash?email=" + email, "", emailHash},
				{http.MethodPost, "/admin/emails-from-hashes", fmt.Sprintf(`{"hashes":[%q]}`, emailHash), email},
			} {
				t.Run(route.target, func(t *testing.T) {
					request := httptest.NewRequest(route.method, route.target, strings.NewReader(route.body))
					request.Header.Set("Content-Type", "application/json")
					request.Header.Set("X-Auth-Token", "fresh-admin-token")
					response := httptest.NewRecorder()
					router.ServeHTTP(response, request)
					require.Equal(t, tt.status, response.Code, response.Body.String())
					if !tt.hosted {
						require.Contains(t, response.Body.String(), route.want)
					}
				})
			}
		})
	}
}
