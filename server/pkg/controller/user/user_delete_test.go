package user

import (
	"database/sql"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/ente/museum/ente"
	enteJWT "github.com/ente/museum/ente/jwt"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	enteTime "github.com/ente/museum/pkg/utils/time"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestSelfDeleteAccountChallengeValidation(t *testing.T) {
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	controller := &UserController{UserRepo: &repo.UserRepository{DB: db}, JwtSecret: []byte("test-jwt-signing-key")}
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	ctx.Request = httptest.NewRequest(http.MethodDelete, "/users/delete", nil)
	ctx.Request.Header.Set("X-Auth-User-ID", "12345")
	for _, tc := range []struct {
		name    string
		userID  int64
		scope   enteJWT.ClaimScope
		expires int64
		valid   bool
	}{
		{"valid", 12345, enteJWT.DELETE_ACCOUNT, enteTime.NMinFromNow(10), true},
		{"other user", 12346, enteJWT.DELETE_ACCOUNT, enteTime.NMinFromNow(10), false},
		{"wrong scope", 12345, enteJWT.PAYMENT, enteTime.NMinFromNow(10), false},
		{"expired", 12345, enteJWT.DELETE_ACCOUNT, enteTime.Microseconds() - 1, false},
	} {
		token, err := controller.GetJWTTokenForClaim(&enteJWT.WebCommonJWTClaim{UserID: tc.userID, ClaimScope: &tc.scope, ExpiryTime: tc.expires})
		require.NoError(t, err)
		for _, prefix := range []string{"", "delete-jwt", "delete-jwtdelete-jwt", "auth-token"} {
			t.Run(tc.name+"/"+prefix, func(t *testing.T) {
				_, err := controller.SelfDeleteAccount(ctx, ente.DeleteAccountRequest{Challenge: prefix + token})
				require.Error(t, err)
				accepted := tc.valid && (prefix == "" || prefix == "delete-jwt")
				require.Equal(t, accepted, errors.Is(err, sql.ErrNoRows), "accepted challenges should reach the missing-user lookup: %v", err)
			})
		}
	}
	otherSigner := &UserController{JwtSecret: []byte("different-jwt-signing-key")}
	wrongSignature, err := otherSigner.GetJWTToken(12345, enteJWT.DELETE_ACCOUNT)
	require.NoError(t, err)
	for _, token := range []string{"malformed", wrongSignature} {
		for _, prefix := range []string{"", "delete-jwt"} {
			_, err := controller.SelfDeleteAccount(ctx, ente.DeleteAccountRequest{Challenge: prefix + token})
			require.Error(t, err)
			require.False(t, errors.Is(err, sql.ErrNoRows))
		}
	}
}
