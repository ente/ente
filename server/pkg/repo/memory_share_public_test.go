package repo

import (
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/stretchr/testify/require"
)

func TestGetPublicMemoryFiles(t *testing.T) {
	db := setupFileUsageTest(t)
	owner := testutil.InsertUser(t, db, testutil.UserFixture{Email: "owner@example.com", CreationTime: 1})
	other := testutil.InsertUser(t, db, testutil.UserFixture{Email: "other@example.com", CreationTime: 1})
	collection := insertObjectTestCollection(t, db, owner)
	anotherCollection := insertObjectTestCollection(t, db, owner)
	first := insertObjectTestFile(t, db, owner)
	second := insertObjectTestFile(t, db, other)
	inactive := insertObjectTestFile(t, db, owner)
	placeholder := insertObjectTestFile(t, db, owner)
	linkObjectTestFileToCollection(t, db, collection, first, owner)
	linkObjectTestFileToCollection(t, db, anotherCollection, first, owner)
	linkObjectTestFileToCollection(t, db, collection, second, owner)
	linkObjectTestFileToCollection(t, db, collection, inactive, owner)
	linkObjectTestFileToCollection(t, db, collection, placeholder, owner)
	_, err := db.Exec(`UPDATE files SET encrypted_metadata = '-' WHERE file_id = $1`, placeholder)
	require.NoError(t, err)
	_, err = db.Exec(`UPDATE collection_files SET is_deleted = true WHERE file_id = $1`, inactive)
	require.NoError(t, err)
	_, err = db.Exec(`UPDATE files SET magic_metadata = $1, pub_magic_metadata = $2 WHERE file_id = $3`,
		ente.MagicMetadata{Version: 1, Count: 1, Data: "private", Header: "header"},
		ente.MagicMetadata{Version: 1, Count: 1, Data: "public", Header: "header"}, first)
	require.NoError(t, err)

	repository := &MemoryShareRepository{DB: db}
	share, err := repository.CreateWithFiles(t.Context(), ente.MemoryShare{
		UserID: owner, Type: ente.MemoryShareTypeShare, EncryptedKey: "key", KeyDecryptionNonce: "nonce", AccessToken: "memory-token",
	}, []ente.MemoryShareFile{
		{FileID: first, FileOwnerID: owner, Position: 2, EncryptedKey: "first-key", KeyDecryptionNonce: "first-nonce"},
		{FileID: second, FileOwnerID: other, Position: 1, EncryptedKey: "second-key", KeyDecryptionNonce: "second-nonce"},
		{FileID: inactive, FileOwnerID: owner, Position: 3},
		{FileID: placeholder, FileOwnerID: owner, Position: 4},
	})
	require.NoError(t, err)
	_, err = repository.CreateWithFiles(t.Context(), ente.MemoryShare{
		UserID: owner, Type: ente.MemoryShareTypeShare, EncryptedKey: "key", KeyDecryptionNonce: "nonce", AccessToken: "other-token",
	}, []ente.MemoryShareFile{{FileID: first, FileOwnerID: owner, EncryptedKey: "other-key", KeyDecryptionNonce: "nonce"}})
	require.NoError(t, err)
	files, err := repository.GetPublicFiles(t.Context(), share.ID)
	require.NoError(t, err)
	require.Len(t, files, 2)
	require.Equal(t, second, files[0].File.ID)
	require.Equal(t, other, files[0].File.OwnerID)
	require.Equal(t, int64(1), files[0].Position)
	require.Equal(t, "second-key", files[0].EncryptedKey)
	require.Equal(t, "second-nonce", files[0].KeyDecryptionNonce)
	require.Equal(t, first, files[1].File.ID)
	require.Equal(t, "first-key", files[1].EncryptedKey)
	require.Equal(t, "file-header", files[1].File.File.DecryptionHeader)
	require.Equal(t, "thumbnail-header", files[1].File.Thumbnail.DecryptionHeader)
	require.Equal(t, "metadata-header", files[1].File.Metadata.DecryptionHeader)
	require.Equal(t, "encrypted-metadata", files[1].File.Metadata.EncryptedData)
	require.Nil(t, files[1].File.MagicMetadata)
	require.Equal(t, &ente.MagicMetadata{Version: 1, Count: 1, Data: "public", Header: "header"}, files[1].File.PublicMagicMetadata)
	empty, err := repository.GetPublicFiles(t.Context(), share.ID+100000)
	require.NoError(t, err)
	require.Equal(t, []ente.PublicMemoryShareFile{}, empty)
}
