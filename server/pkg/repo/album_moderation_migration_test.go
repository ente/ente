package repo

import (
	"os"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestAlbumModerationMigration(t *testing.T) {
	_, db, ownerID := setupCollectionMembershipTest(t)
	collectionID := insertObjectTestCollection(t, db, ownerID)
	newCollectionID := insertObjectTestCollection(t, db, ownerID)
	fileID := insertObjectTestFile(t, db, ownerID)

	up, err := os.ReadFile("migrations/168_album_moderation.up.sql")
	require.NoError(t, err)
	down, err := os.ReadFile("migrations/168_album_moderation.down.sql")
	require.NoError(t, err)
	tx, err := db.BeginTx(t.Context(), nil)
	require.NoError(t, err)
	defer tx.Rollback()

	_, err = tx.Exec(string(down))
	require.NoError(t, err)
	_, err = tx.Exec(`INSERT INTO collection_files
		(collection_id, file_id, encrypted_key, key_decryption_nonce, updation_time, c_owner_id, f_owner_id)
		VALUES ($1, $2, 'legacy-key', 'nonce', 1, $3, $3)`, collectionID, fileID, ownerID)
	require.NoError(t, err)
	_, err = tx.Exec(`INSERT INTO public_collection_tokens (collection_id, access_token)
		VALUES ($1, 'legacy-token')`, collectionID)
	require.NoError(t, err)

	_, err = tx.Exec(string(up))
	require.NoError(t, err)
	var preserved bool
	err = tx.QueryRow(`SELECT f.encrypted_key = 'legacy-key' AND f.moderation_status IS NULL
		AND f.anon_user_id IS NULL AND l.require_approval IS FALSE AND l.access_token = 'legacy-token'
		FROM collection_files f JOIN public_collection_tokens l USING (collection_id)
		WHERE f.collection_id = $1 AND f.file_id = $2`, collectionID, fileID).Scan(&preserved)
	require.NoError(t, err)
	require.True(t, preserved)

	var requiresApproval bool
	err = tx.QueryRow(`INSERT INTO public_collection_tokens (collection_id, access_token)
		VALUES ($1, 'new-token') RETURNING require_approval`, newCollectionID).Scan(&requiresApproval)
	require.NoError(t, err)
	require.False(t, requiresApproval)

	_, err = tx.Exec(string(down))
	require.NoError(t, err)
	err = tx.QueryRow(`SELECT f.encrypted_key = 'legacy-key' AND l.access_token = 'legacy-token'
		FROM collection_files f JOIN public_collection_tokens l USING (collection_id)
		WHERE f.collection_id = $1 AND f.file_id = $2`, collectionID, fileID).Scan(&preserved)
	require.NoError(t, err)
	require.True(t, preserved)
}
