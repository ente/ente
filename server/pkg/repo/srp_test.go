package repo

import (
	"database/sql"
	"testing"
	"time"

	"github.com/ente/museum/internal/testutil"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

func TestSRPSessionValidity(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	repository := &UserAuthRepository{DB: db}

	for _, tc := range []struct {
		name  string
		age   time.Duration
		valid bool
	}{
		{"within validity", srpSessionValidity - time.Minute, true},
		{"past validity", srpSessionValidity + time.Minute, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			sessionID, err := repository.AddSRPSession(uuid.New(), "server-key", "srp-a")
			require.NoError(t, err)
			t.Cleanup(func() {
				_, err := db.Exec(`DELETE FROM srp_sessions WHERE id = $1`, sessionID)
				require.NoError(t, err)
			})
			_, err = db.Exec(`UPDATE srp_sessions SET created_at = now_utc_micro_seconds() - $1 WHERE id = $2`, tc.age.Microseconds(), sessionID)
			require.NoError(t, err)

			_, err = repository.ReserveSrpSessionAttempt(t.Context(), sessionID, 5)
			if tc.valid {
				require.NoError(t, err)
			} else {
				require.ErrorIs(t, err, sql.ErrNoRows)
			}

			claimed, err := repository.TrySetSrpSessionVerified(t.Context(), sessionID)
			require.NoError(t, err)
			require.Equal(t, tc.valid, claimed)
		})
	}
}
