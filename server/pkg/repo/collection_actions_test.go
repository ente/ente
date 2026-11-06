package repo

import (
	"os"
	"testing"

	"github.com/ente/museum/internal/testutil"
	"github.com/stretchr/testify/require"
)

func TestCollectionActionsAppMigration(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	tx, err := db.Begin()
	require.NoError(t, err)
	defer tx.Rollback()
	_, err = tx.Exec(`
	    CREATE TEMP TABLE collection_actions (
	        id TEXT, created_at BIGINT, updated_at BIGINT, is_pending BOOLEAN
	    ) ON COMMIT DROP;
	    CREATE TRIGGER update_collection_actions_updated_at
	        BEFORE UPDATE ON collection_actions
	        FOR EACH ROW EXECUTE PROCEDURE trigger_updated_at_microseconds_column();
	    INSERT INTO collection_actions VALUES ('existing', 1, 2, true);`)
	require.NoError(t, err)
	migration, err := os.ReadFile("migrations/155_collection_actions_app.up.sql")
	require.NoError(t, err)
	_, err = tx.Exec(string(migration))
	require.NoError(t, err)

	var app string
	var createdAt, updatedAt int64
	var pending bool
	require.NoError(t, tx.QueryRow(`SELECT app, created_at, updated_at, is_pending
	    FROM collection_actions WHERE id = 'existing'`).Scan(&app, &createdAt, &updatedAt, &pending))
	require.Equal(t, "photos", app)
	require.EqualValues(t, 1, createdAt)
	require.EqualValues(t, 2, updatedAt)
	require.True(t, pending)
	require.NoError(t, tx.QueryRow(`INSERT INTO collection_actions (id, created_at, updated_at, is_pending)
	    VALUES ('old-writer', 3, 4, true) RETURNING app`).Scan(&app))
	require.Equal(t, "photos", app)

	down, err := os.ReadFile("migrations/155_collection_actions_app.down.sql")
	require.NoError(t, err)
	_, err = tx.Exec(string(down))
	require.NoError(t, err)
	var count int
	require.NoError(t, tx.QueryRow(`SELECT count(*) FROM collection_actions`).Scan(&count))
	require.Equal(t, 2, count)
}
