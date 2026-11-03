package repo

import (
	"testing"

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

	oldRealID, oldFakeID := uuid.New(), uuid.New()
	recentRealID, recentFakeID := uuid.New(), uuid.New()
	_, err = db.Exec(`
		INSERT INTO srp_sessions(id, srp_user_id, server_key, srp_a, is_fake, created_at)
		VALUES
			($1, $5, 'key', 'a', false, now_utc_micro_seconds() - (25::BIGINT * 60 * 60 * 1000 * 1000)),
			($2, $5, 'key', 'a', true, now_utc_micro_seconds() - (25::BIGINT * 60 * 60 * 1000 * 1000)),
			($3, $5, 'key', 'a', false, now_utc_micro_seconds()),
			($4, $5, 'key', 'a', true, now_utc_micro_seconds())`,
		oldRealID, oldFakeID, recentRealID, recentFakeID, uuid.New())
	require.NoError(t, err)

	deleted, err := (&UserAuthRepository{DB: db}).CleanupOldSRPSessions(t.Context())
	require.NoError(t, err)
	require.EqualValues(t, 2, deleted)

	var oldCount, recentCount int
	require.NoError(t, db.QueryRow(`SELECT COUNT(*) FROM srp_sessions WHERE id IN ($1, $2)`, oldRealID, oldFakeID).Scan(&oldCount))
	require.NoError(t, db.QueryRow(`SELECT COUNT(*) FROM srp_sessions WHERE id IN ($1, $2)`, recentRealID, recentFakeID).Scan(&recentCount))
	require.Zero(t, oldCount)
	require.Equal(t, 2, recentCount)
}
