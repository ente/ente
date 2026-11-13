package user

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/passkey"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/patrickmn/go-cache"
	"github.com/stretchr/testify/require"
)

func TestSuspensionBlocksEmailAndSRPLogin(t *testing.T) {
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	const email = "suspended-login@example.com"
	userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: email, CreationTime: 1})
	controller := &UserController{
		UserRepo: &repo.UserRepository{
			DB: db, HashingKey: testutil.HashingKey(), SecretEncryptionKey: testutil.SecretEncryptionKey(),
			PasskeysRepository: &passkey.Repository{DB: db},
		},
		UserAuthRepo: &repo.UserAuthRepository{DB: db},
		Cache:        cache.New(time.Minute, time.Minute),
	}
	srp := &ente.SRPAuthEntity{UserID: userID, SRPUserID: uuid.New(), Salt: "salt", Verifier: "verifier"}
	_, err := db.Exec(`INSERT INTO srp_auth(user_id, srp_user_id, salt, verifier) VALUES($1, $2, $3, $4)`, userID, srp.SRPUserID, srp.Salt, srp.Verifier)
	require.NoError(t, err)
	for _, suspended := range []bool{true, false} {
		require.NoError(t, controller.SetSuspended(context.Background(), userID, suspended))
		for _, srpAuth := range []*ente.SRPAuthEntity{nil, srp} {
			response := httptest.NewRecorder()
			ctx, _ := gin.CreateTestContext(response)
			ctx.Request = httptest.NewRequest(http.MethodPost, "/users/verify-email", nil)
			result, err := controller.onVerificationSuccess(ctx, email, nil, srpAuth)
			if suspended {
				require.ErrorIs(t, err, ente.ErrUserSuspended)
				require.Empty(t, result.Token)
				handler.Error(ctx, err)
				require.Equal(t, http.StatusForbidden, response.Code)
				require.Contains(t, response.Body.String(), "ACCOUNT_SUSPENDED")
			} else {
				require.NoError(t, err)
				require.NotEmpty(t, result.Token)
			}
		}
	}
}
