package repo

import (
	"os"
	"testing"

	"github.com/ente/museum/internal/testutil"
	"github.com/stretchr/testify/require"
)

func TestPendingUploadMetadataMigration(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	tx, err := db.Begin()
	require.NoError(t, err)
	defer tx.Rollback()
	_, err = tx.Exec(`
	    CREATE TEMP TABLE temp_objects (object_key TEXT, expiration_time BIGINT) ON COMMIT DROP;
	    CREATE TEMP TABLE space_temp_objects (object_key TEXT) ON COMMIT DROP;
	    INSERT INTO temp_objects VALUES ('existing', 100);
	    INSERT INTO space_temp_objects VALUES ('existing-space');`)
	require.NoError(t, err)
	migration, err := os.ReadFile("migrations/143_pending_upload_metadata.up.sql")
	require.NoError(t, err)
	_, err = tx.Exec(string(migration))
	require.NoError(t, err)
	var unknown bool
	require.NoError(t, tx.QueryRow(`SELECT user_id IS NULL AND created_at IS NULL AND app IS NULL
	    AND purpose IS NULL AND content_length IS NULL AND content_md5 IS NULL AND client IS NULL
	    FROM temp_objects WHERE object_key = 'existing'`).Scan(&unknown))
	require.True(t, unknown)
	require.NoError(t, tx.QueryRow(`SELECT content_md5 IS NULL AND client IS NULL FROM space_temp_objects`).Scan(&unknown))
	require.True(t, unknown)
	var createdAt int64
	require.NoError(t, tx.QueryRow(`INSERT INTO temp_objects (object_key, expiration_time)
	    VALUES ('old-writer', 200) RETURNING created_at`).Scan(&createdAt))
	require.Positive(t, createdAt)
	down, err := os.ReadFile("migrations/143_pending_upload_metadata.down.sql")
	require.NoError(t, err)
	_, err = tx.Exec(string(down))
	require.NoError(t, err)
	var count int
	require.NoError(t, tx.QueryRow(`SELECT COUNT(*) FROM temp_objects`).Scan(&count))
	require.Equal(t, 2, count)
}
