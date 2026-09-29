package repo

import (
	"os"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestPostMediaMigrationPreservesPhotos(t *testing.T) {
	module := newSpaceTestModule(t)
	ctx := t.Context()
	ownerID := insertSpaceUser(t, module, "media-migration@example.com", "public")
	space, err := testCreateSpace(ctx, module, ownerID, "media_migration", "root", "public", "secret", "nonce", "profile")
	require.NoError(t, err)
	up, err := os.ReadFile("migrations/148_space_post_video.up.sql")
	require.NoError(t, err)
	down, err := os.ReadFile("migrations/148_space_post_video.down.sql")
	require.NoError(t, err)
	tx, err := module.Posts.DB.BeginTx(ctx, nil)
	require.NoError(t, err)
	defer tx.Rollback()
	_, err = tx.ExecContext(ctx, string(down))
	require.NoError(t, err)
	var postID int64
	err = tx.QueryRowContext(ctx, `
		INSERT INTO space_posts (space_id, encrypted_post_key)
		VALUES ($1, $2) RETURNING post_id
	`, space.SpaceID, []byte("post-key")).Scan(&postID)
	require.NoError(t, err)
	_, err = tx.ExecContext(ctx, `
		INSERT INTO space_post_assets (post_id, object_key, bucket_id, position, metadata_cipher)
		VALUES ($1, 'legacy-photo', 'test-bucket', 0, $2)
	`, postID, []byte("legacy-metadata"))
	require.NoError(t, err)
	_, err = tx.ExecContext(ctx, string(up))
	require.NoError(t, err)
	var role string
	var metadata []byte
	err = tx.QueryRowContext(ctx, `
		SELECT role, metadata_cipher FROM space_post_assets WHERE object_key = 'legacy-photo'
	`).Scan(&role, &metadata)
	require.NoError(t, err)
	require.Equal(t, "preview", role)
	require.Equal(t, []byte("legacy-metadata"), metadata)
	_, err = tx.ExecContext(ctx, `
		INSERT INTO space_post_assets (post_id, object_key, bucket_id, position, metadata_cipher, role)
		VALUES ($1, 'video', 'test-bucket', 0, $2, 'video')
	`, postID, []byte("video-metadata"))
	require.NoError(t, err)
	_, err = tx.ExecContext(ctx, string(down))
	require.ErrorContains(t, err, "Cannot roll back while video posts exist")
}
