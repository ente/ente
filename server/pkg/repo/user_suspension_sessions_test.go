package repo_test

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	castrepo "github.com/ente/museum/pkg/repo/cast"
	"github.com/ente/museum/pkg/utils/auth"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestAccountSuspensionRevokesSpaceAndCastSessions(t *testing.T) {
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	ctx := context.Background()
	r := &repo.UserAuthRepository{DB: db}
	spaceSessions := &spacerepo.SessionsRepository{DB: db}
	castSessions := &castrepo.Repository{DB: db}
	userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "sessions@example.com", CreationTime: 1})
	otherID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "other-sessions@example.com", CreationTime: 1})
	expiresAt := time.Now().Add(time.Hour).UnixMicro()
	for token, owner := range map[string]int64{"old-session": userID, "other-session": otherID} {
		hash := auth.HashToken(token)
		require.NoError(t, spaceSessions.CreateBrowserSession(ctx, hash[:], owner, "wrap-key", expiresAt))
		code, err := castSessions.AddCode(ctx, "public-key", nil, "127.0.0.1", "device")
		require.NoError(t, err)
		_, err = castSessions.InsertCastData(ctx, owner, code, 42, token, "payload")
		require.NoError(t, err)
	}
	code, err := castSessions.AddCode(ctx, "public-key", nil, "127.0.0.1", "new-device")
	require.NoError(t, err)
	require.NoError(t, r.AddToken(userID, ente.Photos, "bootstrap", "", ""))
	bootstrapHash := auth.HashToken("bootstrap")
	newHash := auth.HashToken("new-session")
	_, err = r.SetUserSuspended(ctx, userID, true)
	require.NoError(t, err)
	require.ErrorIs(t, spaceSessions.CreateBrowserSession(ctx, newHash[:], userID, "wrap-key", expiresAt), ente.ErrUserSuspended)
	require.ErrorIs(t, spaceSessions.ExchangeBrowserSession(ctx, bootstrapHash[:], newHash[:], userID, "wrap-key", expiresAt), ente.ErrUserSuspended)
	_, err = castSessions.InsertCastData(ctx, userID, code, 42, "new-session", "payload")
	require.ErrorIs(t, err, ente.ErrUserSuspended)

	oldHash := auth.HashToken("old-session")
	_, err = spaceSessions.GetBrowserSession(ctx, oldHash[:])
	require.ErrorIs(t, err, sql.ErrNoRows)
	_, _, err = castSessions.GetCollectionAndCasterIDForToken(ctx, "old-session")
	require.Error(t, err)
	otherHash := auth.HashToken("other-session")
	_, err = spaceSessions.GetBrowserSession(ctx, otherHash[:])
	require.NoError(t, err)
	_, casterID, err := castSessions.GetCollectionAndCasterIDForToken(ctx, "other-session")
	require.NoError(t, err)
	require.Equal(t, otherID, casterID)
	_, err = r.SetUserSuspended(ctx, userID, false)
	require.NoError(t, err)
	require.NoError(t, r.AddToken(userID, ente.Photos, "fresh-bootstrap", "", ""))
	freshHash := auth.HashToken("fresh-bootstrap")
	require.NoError(t, spaceSessions.ExchangeBrowserSession(ctx, freshHash[:], newHash[:], userID, "wrap-key", expiresAt))
	_, err = spaceSessions.GetBrowserSession(ctx, newHash[:])
	require.NoError(t, err)
	_, err = castSessions.InsertCastData(ctx, userID, code, 42, "new-session", "payload")
	require.NoError(t, err)
	_, casterID, err = castSessions.GetCollectionAndCasterIDForToken(ctx, "new-session")
	require.NoError(t, err)
	require.Equal(t, userID, casterID)
}

func TestSpaceAndCastSessionCreationWaitsForSuspension(t *testing.T) {
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	ctx := context.Background()
	spaceSessions := &spacerepo.SessionsRepository{DB: db}
	castSessions := &castrepo.Repository{DB: db}
	for _, kind := range []string{"space", "space-exchange", "cast"} {
		t.Run(kind, func(t *testing.T) {
			userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: kind + "-race@example.com", CreationTime: 1})
			require.NoError(t, (&repo.UserAuthRepository{DB: db}).AddToken(userID, ente.Photos, kind, "", ""))
			bootstrapHash := auth.HashToken(kind)
			sessionHash := auth.HashToken(kind + "-session")
			code, err := castSessions.AddCode(ctx, "public-key", nil, "127.0.0.1", "device")
			require.NoError(t, err)
			tx, err := db.Begin()
			require.NoError(t, err)
			defer tx.Rollback()
			_, err = tx.Exec(`UPDATE users SET is_suspended = true WHERE user_id = $1`, userID)
			require.NoError(t, err)
			var pid int
			require.NoError(t, tx.QueryRow(`SELECT pg_backend_pid()`).Scan(&pid))
			done := make(chan error, 1)
			go func() {
				expiresAt := time.Now().Add(time.Hour).UnixMicro()
				switch kind {
				case "space":
					done <- spaceSessions.CreateBrowserSession(ctx, sessionHash[:], userID, "wrap-key", expiresAt)
				case "space-exchange":
					done <- spaceSessions.ExchangeBrowserSession(ctx, bootstrapHash[:], sessionHash[:], userID, "wrap-key", expiresAt)
				case "cast":
					_, err := castSessions.InsertCastData(ctx, userID, code, 42, kind+"-session", "payload")
					done <- err
				}
			}()
			require.EventuallyWithT(t, func(collect *assert.CollectT) {
				var blocked bool
				require.NoError(collect, db.QueryRow(`SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE datname = current_database() AND $1 = ANY(pg_blocking_pids(pid)))`, pid).Scan(&blocked))
				require.True(collect, blocked)
			}, 5*time.Second, 10*time.Millisecond)
			require.NoError(t, tx.Commit())
			select {
			case err := <-done:
				require.ErrorIs(t, err, ente.ErrUserSuspended)
			case <-time.After(5 * time.Second):
				t.Fatal("session creation did not finish")
			}
			var count int
			require.NoError(t, db.QueryRow(`SELECT count(*) FROM space_browser_sessions WHERE user_id = $1`, userID).Scan(&count))
			require.Zero(t, count)
			_, _, err = castSessions.GetCollectionAndCasterIDForToken(ctx, kind+"-session")
			require.Error(t, err)
		})
	}
}
