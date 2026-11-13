package authsession_test

import (
	"database/sql"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/controller/authsession"
	"github.com/ente/museum/pkg/controller/user"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/patrickmn/go-cache"
	"github.com/stretchr/testify/require"
)

func TestHashKeyedSessionRevocation(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "hash-revocation@example.com", CreationTime: 1})
	userAuthRepo := &repo.UserAuthRepository{DB: db}
	authCache := cache.New(time.Minute, time.Minute)
	controller := &user.UserController{UserAuthRepo: userAuthRepo, Cache: authCache}
	currentToken := "current-token"
	otherToken := "other-token"
	require.NoError(t, userAuthRepo.AddToken(userID, ente.Photos, currentToken, "127.0.0.1", "test"))
	require.NoError(t, userAuthRepo.AddToken(userID, ente.Photos, otherToken, "127.0.0.1", "test"))

	currentHash := auth.HashToken(currentToken)
	otherHash := auth.HashToken(otherToken)
	_, _, _, err := authsession.Authenticate(userAuthRepo, authCache, currentHash[:], ente.Photos)
	require.NoError(t, err)
	_, _, _, err = authsession.Authenticate(userAuthRepo, authCache, otherHash[:], ente.Photos)
	require.NoError(t, err)

	require.NoError(t, controller.RemoveAllOtherTokens(userID, currentToken))
	_, _, _, err = authsession.Authenticate(userAuthRepo, authCache, otherHash[:], ente.Photos)
	require.ErrorIs(t, err, sql.ErrNoRows)
	authCache.Flush()
	_, _, _, err = authsession.Authenticate(userAuthRepo, authCache, currentHash[:], ente.Photos)
	require.NoError(t, err)

	require.NoError(t, controller.TerminateSession(userID, currentToken))
	_, _, _, err = authsession.Authenticate(userAuthRepo, authCache, currentHash[:], ente.Photos)
	require.ErrorIs(t, err, sql.ErrNoRows)
}
