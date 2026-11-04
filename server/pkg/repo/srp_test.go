package repo

import (
	"database/sql"
	"testing"
	"time"

	"github.com/ente/museum/internal/testutil"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

func TestCleanupOldSRPSessions(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	_, err := db.Exec(`TRUNCATE TABLE srp_sessions`)
	require.NoError(t, err)
	t.Cleanup(func() {
		_, err := db.Exec(`TRUNCATE TABLE srp_sessions`)
		require.NoError(t, err)
	})

	oldRealID, oldFakeID, anotherOldRealID := uuid.New(), uuid.New(), uuid.New()
	recentRealID, recentFakeID := uuid.New(), uuid.New()
	_, err = db.Exec(`
		INSERT INTO srp_sessions(id, srp_user_id, server_key, srp_a, is_fake, created_at)
		VALUES
			($1, $6, 'key', 'a', false, now_utc_micro_seconds() - (25::BIGINT * 60 * 60 * 1000 * 1000)),
			($2, $6, 'key', 'a', true, now_utc_micro_seconds() - (25::BIGINT * 60 * 60 * 1000 * 1000)),
			($3, $6, 'key', 'a', false, now_utc_micro_seconds() - (25::BIGINT * 60 * 60 * 1000 * 1000)),
			($4, $6, 'key', 'a', false, now_utc_micro_seconds()),
			($5, $6, 'key', 'a', true, now_utc_micro_seconds())`,
		oldRealID, oldFakeID, anotherOldRealID, recentRealID, recentFakeID, uuid.New())
	require.NoError(t, err)

	repository := &UserAuthRepository{DB: db}
	deleted, err := repository.CleanupOldSRPSessions(t.Context(), 2)
	require.NoError(t, err)
	require.EqualValues(t, 2, deleted)

	var oldCount, recentCount int
	require.NoError(t, db.QueryRow(`SELECT COUNT(*) FROM srp_sessions WHERE id IN ($1, $2, $3)`, oldRealID, oldFakeID, anotherOldRealID).Scan(&oldCount))
	require.NoError(t, db.QueryRow(`SELECT COUNT(*) FROM srp_sessions WHERE id IN ($1, $2)`, recentRealID, recentFakeID).Scan(&recentCount))
	require.Equal(t, 1, oldCount)
	require.Equal(t, 2, recentCount)

	deleted, err = repository.CleanupOldSRPSessions(t.Context(), 2)
	require.NoError(t, err)
	require.EqualValues(t, 1, deleted)
	require.NoError(t, db.QueryRow(`SELECT COUNT(*) FROM srp_sessions WHERE id IN ($1, $2, $3)`, oldRealID, oldFakeID, anotherOldRealID).Scan(&oldCount))
	require.Zero(t, oldCount)
}

func TestSRPSessionValidity(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	_, err := db.Exec(`TRUNCATE TABLE srp_sessions`)
	require.NoError(t, err)
	t.Cleanup(func() {
		_, err := db.Exec(`TRUNCATE TABLE srp_sessions`)
		require.NoError(t, err)
	})
	repository := &UserAuthRepository{DB: db}

	for _, test := range []struct {
		name  string
		age   time.Duration
		valid bool
	}{
		{"within validity", srpSessionValidity - time.Minute, true},
		{"past validity", srpSessionValidity + time.Minute, false},
	} {
		t.Run(test.name, func(t *testing.T) {
			sessionID, err := repository.AddSRPSession(uuid.New(), "server-key", "srp-a")
			require.NoError(t, err)
			t.Cleanup(func() {
				_, err := db.Exec(`DELETE FROM srp_sessions WHERE id = $1`, sessionID)
				require.NoError(t, err)
			})
			_, err = db.Exec(`UPDATE srp_sessions SET created_at = now_utc_micro_seconds() - $1 WHERE id = $2`, test.age.Microseconds(), sessionID)
			require.NoError(t, err)

			_, err = repository.ReserveSrpSessionAttempt(t.Context(), sessionID, 5)
			if test.valid {
				require.NoError(t, err)
			} else {
				require.ErrorIs(t, err, sql.ErrNoRows)
			}

			claimed, err := repository.TrySetSrpSessionVerified(t.Context(), sessionID)
			require.NoError(t, err)
			require.Equal(t, test.valid, claimed)
		})
	}

	t.Run("expires after reservation", func(t *testing.T) {
		sessionID, err := repository.AddSRPSession(uuid.New(), "server-key", "srp-a")
		require.NoError(t, err)
		t.Cleanup(func() {
			_, err := db.Exec(`DELETE FROM srp_sessions WHERE id = $1`, sessionID)
			require.NoError(t, err)
		})
		_, err = repository.ReserveSrpSessionAttempt(t.Context(), sessionID, 5)
		require.NoError(t, err)
		_, err = db.Exec(`UPDATE srp_sessions SET created_at = now_utc_micro_seconds() - $1 WHERE id = $2`, (srpSessionValidity + time.Minute).Microseconds(), sessionID)
		require.NoError(t, err)

		claimed, err := repository.TrySetSrpSessionVerified(t.Context(), sessionID)
		require.NoError(t, err)
		require.False(t, claimed)
		session, err := repository.GetSrpSessionEntity(t.Context(), sessionID)
		require.NoError(t, err)
		require.False(t, session.IsVerified)
		require.True(t, session.IsExpired)
	})
}
