package repo

import (
	"context"
	"database/sql"
	"fmt"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestAccountSuspension(t *testing.T) {
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "suspended@example.com", CreationTime: 1})
	otherID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "other@example.com", CreationTime: 1})
	r := &UserAuthRepository{DB: db}
	ctx := context.Background()
	for _, app := range []ente.App{ente.Photos, ente.Auth, ente.Locker} {
		require.NoError(t, r.AddToken(userID, app, string(app), "", ""))
	}
	require.NoError(t, r.AddToken(otherID, ente.Photos, "other", "", ""))
	hash := auth.HashToken("photos")
	_, err := db.Exec(`INSERT INTO push_tokens(user_id, fcm_token, session_token_hash) VALUES($1, 'device', $2)`, userID, hash[:])
	require.NoError(t, err)

	tokens, err := r.SetUserSuspended(ctx, userID, true)
	require.NoError(t, err)
	require.Len(t, tokens, 3)
	var activeTokens int
	require.NoError(t, db.QueryRow(`SELECT count(*) FROM tokens WHERE user_id = $1 AND is_deleted = false`, userID).Scan(&activeTokens))
	require.Zero(t, activeTokens)
	var pushTokens int
	require.NoError(t, db.QueryRow(`SELECT count(*) FROM push_tokens WHERE user_id = $1`, userID).Scan(&pushTokens))
	require.Zero(t, pushTokens)
	_, _, err = r.GetUserIDWithTokenHash(hash[:], ente.Photos)
	require.ErrorIs(t, err, sql.ErrNoRows)
	var suspended bool
	require.NoError(t, db.QueryRow(`SELECT is_suspended FROM users WHERE user_id = $1`, userID).Scan(&suspended))
	require.True(t, suspended)

	for _, app := range []ente.App{ente.Photos, ente.Auth, ente.Locker} {
		t.Run(string(app), func(t *testing.T) {
			require.ErrorIs(t, r.AddToken(userID, app, "new", "", ""), ente.ErrUserSuspended)
			require.ErrorIs(t, r.AddLoginResult(ctx, userID, nil, nil, app, "new", "", "", "", "", 0, false), ente.ErrUserSuspended)
			require.ErrorIs(t, r.AddLoginResult(ctx, userID, nil, nil, app, "", "", "", "new-passkey", "new-totp", time.Now().Add(time.Hour).UnixMicro(), false), ente.ErrUserSuspended)
			for _, pending := range []PendingLoginSession{TOTPPendingLogin, PasskeyPendingLogin} {
				require.ErrorIs(t, r.AddTokenForPendingLogin(ctx, userID, "pending", pending, true, app, "new", "", "", nil), ente.ErrUserSuspended)
			}
		})
	}
	_, err = r.SetUserSuspended(ctx, userID, true)
	require.NoError(t, err)
	for range 2 {
		_, err = r.SetUserSuspended(ctx, userID, false)
		require.NoError(t, err)
	}
	require.NoError(t, r.AddToken(userID, ente.Photos, "new", "", ""))
	for _, token := range []string{"new", "other"} {
		hash := auth.HashToken(token)
		_, expired, err := r.GetUserIDWithTokenHash(hash[:], ente.Photos)
		require.NoError(t, err)
		require.False(t, expired)
	}
	_, err = r.SetUserSuspended(ctx, -1, true)
	require.ErrorIs(t, err, sql.ErrNoRows)
	require.NoError(t, (&UserRepository{DB: db}).Delete(otherID))
	for _, suspended := range []bool{true, false} {
		_, err = r.SetUserSuspended(ctx, otherID, suspended)
		require.ErrorIs(t, err, ente.ErrUserDeleted)
	}
}

func TestSuspensionRemovesAllPushRegistrations(t *testing.T) {
	db := testutil.RequireTestDB(t)
	for _, activeSession := range []bool{false, true} {
		t.Run(fmt.Sprintf("active_session_%t", activeSession), func(t *testing.T) {
			testutil.ResetTables(t, db)
			t.Cleanup(func() { testutil.ResetTables(t, db) })
			userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "suspended@example.com", CreationTime: 1})
			otherID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "other@example.com", CreationTime: 1})
			r := &UserAuthRepository{DB: db}
			if activeSession {
				require.NoError(t, r.AddToken(userID, ente.Photos, "session", "", ""))
			}
			hash := auth.HashToken("session")
			_, err := db.Exec(`INSERT INTO push_tokens(user_id, fcm_token, session_token_hash, last_notified_at)
				VALUES ($1, 'legacy', NULL, 1), ($1, 'session', $2, 1), ($3, 'other', NULL, 1)`, userID, hash[:], otherID)
			require.NoError(t, err)
			_, err = r.SetUserSuspended(context.Background(), userID, true)
			require.NoError(t, err)
			var count int
			require.NoError(t, db.QueryRow(`SELECT count(*) FROM push_tokens WHERE user_id = $1`, userID).Scan(&count))
			require.Zero(t, count)
			notifications, err := (&PushTokenRepository{DB: db}).GetTokensToBeNotified(2, 10)
			require.NoError(t, err)
			require.Len(t, notifications, 1)
			require.Equal(t, otherID, notifications[0].UserID)
			require.Equal(t, "other", notifications[0].FCMToken)
		})
	}
}

func TestSuspensionRollback(t *testing.T) {
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "rollback@example.com", CreationTime: 1})
	r := &UserAuthRepository{DB: db}
	require.NoError(t, r.AddToken(userID, ente.Photos, "session", "", ""))
	_, err := db.Exec(`INSERT INTO push_tokens(user_id, fcm_token) VALUES ($1, 'legacy')`, userID)
	require.NoError(t, err)
	_, err = db.Exec(`CREATE FUNCTION fail_suspension_cleanup() RETURNS trigger LANGUAGE plpgsql AS $$
		BEGIN RAISE EXCEPTION 'cleanup failed'; END; $$;
		CREATE TRIGGER fail_suspension_cleanup BEFORE DELETE ON push_tokens
		FOR EACH ROW EXECUTE FUNCTION fail_suspension_cleanup()`)
	require.NoError(t, err)
	t.Cleanup(func() {
		_, err := db.Exec(`DROP TRIGGER fail_suspension_cleanup ON push_tokens; DROP FUNCTION fail_suspension_cleanup()`)
		require.NoError(t, err)
	})
	_, err = r.SetUserSuspended(context.Background(), userID, true)
	require.ErrorContains(t, err, "cleanup failed")
	var suspended bool
	require.NoError(t, db.QueryRow(`SELECT is_suspended FROM users WHERE user_id = $1`, userID).Scan(&suspended))
	require.False(t, suspended)
	hash := auth.HashToken("session")
	_, _, err = r.GetUserIDWithTokenHash(hash[:], ente.Photos)
	require.NoError(t, err)
	var count int
	require.NoError(t, db.QueryRow(`SELECT count(*) FROM push_tokens WHERE user_id = $1`, userID).Scan(&count))
	require.Equal(t, 1, count)
}

func TestSuspensionSerializesWithLogin(t *testing.T) {
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	r := &UserAuthRepository{DB: db}
	for _, suspensionFirst := range []bool{true, false} {
		t.Run(fmt.Sprintf("suspension_first_%t", suspensionFirst), func(t *testing.T) {
			userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: fmt.Sprintf("race-%t@example.com", suspensionFirst), CreationTime: 1})
			tx, err := db.Begin()
			require.NoError(t, err)
			defer tx.Rollback()
			var gatePID int
			require.NoError(t, tx.QueryRow(`SELECT pg_backend_pid()`).Scan(&gatePID))
			blockingPID := gatePID
			token := fmt.Sprintf("race-%t", suspensionFirst)
			done := make(chan error, 1)
			var loginDone chan error
			if suspensionFirst {
				_, err = tx.Exec(`UPDATE users SET is_suspended = true WHERE user_id = $1`, userID)
				require.NoError(t, err)
				go func() { done <- r.AddToken(userID, ente.Photos, token, "", "") }()
			} else {
				_, err = tx.Exec(`LOCK TABLE tokens IN EXCLUSIVE MODE`)
				require.NoError(t, err)
				loginDone = make(chan error, 1)
				go func() { loginDone <- r.AddToken(userID, ente.Photos, token, "", "") }()
				require.EventuallyWithT(t, func(collect *assert.CollectT) {
					require.NoError(collect, db.QueryRow(`SELECT pid FROM pg_stat_activity WHERE datname = current_database() AND $1 = ANY(pg_blocking_pids(pid))`, gatePID).Scan(&blockingPID))
				}, 5*time.Second, 10*time.Millisecond)
				go func() {
					_, err := r.SetUserSuspended(context.Background(), userID, true)
					done <- err
				}()
			}
			require.EventuallyWithT(t, func(collect *assert.CollectT) {
				var blocked bool
				require.NoError(collect, db.QueryRow(`SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE datname = current_database() AND $1 = ANY(pg_blocking_pids(pid)))`, blockingPID).Scan(&blocked))
				require.True(collect, blocked)
			}, 5*time.Second, 10*time.Millisecond)
			require.NoError(t, tx.Commit())
			if loginDone != nil {
				select {
				case err := <-loginDone:
					require.NoError(t, err)
				case <-time.After(5 * time.Second):
					t.Fatal("login did not finish")
				}
			}
			select {
			case err := <-done:
				if suspensionFirst {
					require.ErrorIs(t, err, ente.ErrUserSuspended)
				} else {
					require.NoError(t, err)
				}
			case <-time.After(5 * time.Second):
				t.Fatal("concurrent operation did not finish")
			}
			var count int
			require.NoError(t, db.QueryRow(`SELECT count(*) FROM tokens WHERE user_id = $1 AND is_deleted = false`, userID).Scan(&count))
			require.Zero(t, count)
		})
	}
}
