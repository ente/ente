package collections

import (
	"errors"
	"strings"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller/access"
	memoryshare "github.com/ente/museum/pkg/controller/memory_share"
	"github.com/ente/museum/pkg/controller/public"
	"github.com/ente/museum/pkg/repo"
	publicrepo "github.com/ente/museum/pkg/repo/public"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/stretchr/testify/require"
)

func TestCollectionActionCreationApp(t *testing.T) {
	db, collectionRepo, ownerID, adminID := setupCollectionShareTest(t)
	t.Cleanup(func() {
		_, err := db.Exec(`DELETE FROM collection_actions`)
		require.NoError(t, err)
	})
	controller := &CollectionController{
		AccessCtrl:            access.NewAccessController(collectionRepo, nil),
		CollectionRepo:        collectionRepo,
		FileRepo:              &repo.FileRepository{DB: db},
		CollectionActionsRepo: &repo.CollectionActionsRepository{DB: db},
	}
	for _, app := range []ente.App{ente.Photos, ente.Locker} {
		for _, action := range []string{ente.ActionRemove, ente.ActionDeleteSuggested} {
			t.Run(string(app)+"/"+action, func(t *testing.T) {
				collection, err := collectionRepo.Create(ente.Collection{
					Owner: ente.CollectionUser{ID: ownerID}, App: string(app), Type: "album",
					EncryptedKey: "key", KeyDecryptionNonce: "nonce", Name: "collection", UpdationTime: 1,
				})
				require.NoError(t, err)
				addShareTestShare(t, collectionRepo, collection.ID, ownerID, adminID, ente.ADMIN)
				fileIDs := []int64{
					addShareTestOwnerFile(t, db, collection.ID, ownerID),
					addShareTestOwnerFile(t, db, collection.ID, ownerID),
				}
				ctx := newBatchShareTestContext(adminID)
				ctx.Set(auth.AppContextKey, app)
				if action == ente.ActionRemove {
					err = controller.RemoveFilesV3(ctx, adminID, ente.RemoveFilesV3Request{CollectionID: collection.ID, FileIDs: fileIDs})
				} else {
					err = controller.SuggestDeleteInSharedCollection(ctx, ente.SuggestDeleteRequest{CollectionID: collection.ID, FileIDs: fileIDs})
				}
				require.NoError(t, err)
				rows, err := db.Query(`SELECT app, action, file_id FROM collection_actions
				    WHERE collection_id = $1 ORDER BY file_id`, collection.ID)
				require.NoError(t, err)
				defer rows.Close()
				actions := make(map[string][]int64)
				for rows.Next() {
					var storedApp, storedAction string
					var fileID int64
					require.NoError(t, rows.Scan(&storedApp, &storedAction, &fileID))
					require.Equal(t, string(app), storedApp)
					actions[storedAction] = append(actions[storedAction], fileID)
				}
				require.NoError(t, rows.Err())
				want := map[string][]int64{ente.ActionRemove: fileIDs}
				if action == ente.ActionDeleteSuggested {
					want[ente.ActionDeleteSuggested] = fileIDs
				}
				require.Equal(t, want, actions)
			})
		}
	}
}

func TestPendingUploadsCannotBePublished(t *testing.T) {
	db, collections, ownerID, _ := setupCollectionShareTest(t)
	albumID := createShareTestCollection(t, collections, ownerID)
	ordinary := addShareTestOwnerFile(t, db, albumID, ownerID)
	pending := addShareTestOwnerFile(t, db, albumID, ownerID)
	_, err := db.Exec(`UPDATE collection_files SET moderation_status = 'PENDING' WHERE file_id = $1`, pending)
	require.NoError(t, err)
	files := &repo.FileRepository{DB: db}
	ctx := newBatchShareTestContext(ownerID)

	t.Run("file link", func(t *testing.T) {
		links := &public.FileLinkController{FileRepo: files, FileLinkRepo: publicrepo.NewFileLinkRepo(db)}
		_, err := links.CreateLink(ctx, ente.CreateFileUrl{FileID: pending, App: ente.Photos})
		requireBadRequestError(t, err)
		link, err := links.CreateLink(ctx, ente.CreateFileUrl{FileID: ordinary, App: ente.Photos})
		require.NoError(t, err)
		require.Equal(t, ordinary, link.FileID)
		published, err := links.GetUrls(ctx, 0, 10)
		require.NoError(t, err)
		require.Len(t, published, 1)
		require.Equal(t, ordinary, published[0].FileID)
	})

	t.Run("memory share", func(t *testing.T) {
		memories := memoryshare.NewController(repo.NewMemoryShareRepository(db), files, access.NewAccessController(collections, files))
		req := ente.CreateMemoryShareRequest{
			EncryptedKey: "memory-key", KeyDecryptionNonce: "nonce",
			Files: []ente.MemoryShareFileItem{
				{FileID: ordinary, EncryptedKey: "ordinary-key", KeyDecryptionNonce: "nonce"},
				{FileID: pending, EncryptedKey: "pending-key", KeyDecryptionNonce: "nonce"},
			},
		}
		_, err := memories.Create(ctx, ownerID, req)
		requireBadRequestError(t, err)
		req.Files = req.Files[:1]
		created, err := memories.Create(ctx, ownerID, req)
		require.NoError(t, err)
		published, err := memories.List(ctx, ownerID)
		require.NoError(t, err)
		require.Len(t, published.MemoryShares, 1)
		require.Equal(t, created.MemoryShare.ID, published.MemoryShares[0].ID)
	})
}

func TestMoveFilesRejectsSameCollection(t *testing.T) {
	const collectionID = int64(1)
	err := (&CollectionController{}).MoveFiles(nil, ente.MoveFilesRequest{
		FromCollectionID: collectionID,
		ToCollectionID:   collectionID,
	})
	var apiErr *ente.ApiError
	if !errors.As(err, &apiErr) || apiErr.Code != ente.BadRequest {
		t.Fatalf("MoveFiles() error = %v, want %s", err, ente.BadRequest)
	}
}

func TestCollectionFileActionsRejectInvalidItems(t *testing.T) {
	controller := &CollectionController{}
	valid := ente.CollectionFileItem{
		ID:                 1,
		EncryptedKey:       b64OfLen(encryptedCollectionKeyLen),
		KeyDecryptionNonce: b64OfLen(secretboxNonceBytes),
	}
	if err := validateCollectionFileItems([]ente.CollectionFileItem{valid}); err != nil {
		t.Fatalf("valid item rejected: %v", err)
	}
	add := func(files []ente.CollectionFileItem) error { return controller.AddFiles(nil, 1, files, 1) }
	restore := func(files []ente.CollectionFileItem) error { return controller.RestoreFiles(nil, 1, 1, files) }
	move := func(files []ente.CollectionFileItem) error {
		return controller.MoveFiles(nil, ente.MoveFilesRequest{FromCollectionID: 1, ToCollectionID: 2, Files: files})
	}
	copyFiles := func(files []ente.CollectionFileItem) error {
		return controller.IsCopyAllowed(nil, 1, ente.CopyFileSyncRequest{SrcCollectionID: 1, DstCollection: 2, CollectionFileItems: files})
	}
	tests := []struct {
		name    string
		invalid ente.CollectionFileItem
		call    func([]ente.CollectionFileItem) error
	}{
		{"add missing ID", ente.CollectionFileItem{EncryptedKey: valid.EncryptedKey, KeyDecryptionNonce: valid.KeyDecryptionNonce}, add},
		{"add short key", ente.CollectionFileItem{ID: 2, EncryptedKey: b64OfLen(encryptedCollectionKeyLen - 1), KeyDecryptionNonce: valid.KeyDecryptionNonce}, add},
		{"restore missing key", ente.CollectionFileItem{ID: 2, KeyDecryptionNonce: valid.KeyDecryptionNonce}, restore},
		{"move missing nonce", ente.CollectionFileItem{ID: 2, EncryptedKey: valid.EncryptedKey}, move},
		{"copy missing ID", ente.CollectionFileItem{EncryptedKey: valid.EncryptedKey, KeyDecryptionNonce: valid.KeyDecryptionNonce}, copyFiles},
		{"copy short key", ente.CollectionFileItem{ID: 2, EncryptedKey: b64OfLen(encryptedCollectionKeyLen - 1), KeyDecryptionNonce: valid.KeyDecryptionNonce}, copyFiles},
		{"copy invalid base64 key", ente.CollectionFileItem{ID: 2, EncryptedKey: strings.Repeat("!", len(valid.EncryptedKey)), KeyDecryptionNonce: valid.KeyDecryptionNonce}, copyFiles},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.call([]ente.CollectionFileItem{valid, tt.invalid})
			var apiErr *ente.ApiError
			if !errors.As(err, &apiErr) || apiErr.Code != ente.BadRequest {
				t.Fatalf("error = %v, want %s", err, ente.BadRequest)
			}
		})
	}
}
