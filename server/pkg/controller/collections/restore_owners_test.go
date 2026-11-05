package collections

import (
	"errors"
	"net/http/httptest"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/controller/access"
	"github.com/ente/museum/pkg/repo"
	"github.com/gin-gonic/gin"
)

func TestRestoreFilesOwnership(t *testing.T) {
	db, collectionRepo, ownerID, otherID := setupCollectionShareTest(t)
	testutil.InsertUsage(t, db, ownerID, 0)
	collectionRepo.TrashRepo = &repo.TrashRepository{DB: db}
	collectionID := createShareTestCollection(t, collectionRepo, ownerID)
	fileID := addShareTestOwnerFile(t, db, collectionID, ownerID)
	secondFileID := addShareTestOwnerFile(t, db, collectionID, ownerID)
	otherCollectionID := createShareTestCollection(t, collectionRepo, otherID)
	otherFileID := addShareTestOwnerFile(t, db, otherCollectionID, otherID)
	if _, err := db.Exec(`UPDATE collection_files SET is_deleted = TRUE WHERE collection_id = $1 AND file_id IN ($2, $3)`, collectionID, fileID, secondFileID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO trash(file_id, user_id, collection_id, delete_by) VALUES($1, $3, $4, $3), ($2, $3, $4, $3)`, fileID, secondFileID, ownerID, collectionID); err != nil {
		t.Fatal(err)
	}
	fileRepo := &repo.FileRepository{DB: db}
	c := &CollectionController{CollectionRepo: collectionRepo, FileRepo: fileRepo, AccessCtrl: access.NewAccessController(collectionRepo, fileRepo)}
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	ctx.Request = httptest.NewRequest("POST", "/collections/restore-files", nil)
	item := func(id int64) ente.CollectionFileItem {
		return ente.CollectionFileItem{ID: id, EncryptedKey: b64OfLen(encryptedCollectionKeyLen), KeyDecryptionNonce: b64OfLen(secretboxNonceBytes)}
	}
	assertRestoredCount := func(t *testing.T, want int) {
		t.Helper()
		var active, restored int
		if err := db.QueryRow(`SELECT
			count(*) FILTER (WHERE NOT cf.is_deleted),
			count(*) FILTER (WHERE t.is_restored)
			FROM collection_files cf JOIN trash t ON t.file_id = cf.file_id
			WHERE cf.collection_id = $1 AND cf.file_id IN ($2, $3) AND t.user_id = $4`,
			collectionID, fileID, secondFileID, ownerID).Scan(&active, &restored); err != nil {
			t.Fatal(err)
		}
		if active != want || restored != want {
			t.Fatalf("active = %d, restored = %d, want both %d", active, restored, want)
		}
	}
	missingID := otherFileID + 10000
	for _, tc := range []struct {
		name string
		ids  []int64
		want error
	}{
		{"empty", nil, ente.ErrBadRequest},
		{"missing", []int64{missingID}, ente.ErrBadRequest},
		{"owned and missing", []int64{fileID, missingID}, ente.ErrBadRequest},
		{"other owner", []int64{otherFileID}, ente.ErrPermissionDenied},
		{"owned and other owner", []int64{fileID, otherFileID}, ente.ErrPermissionDenied},
		{"missing first", []int64{missingID, otherFileID}, ente.ErrPermissionDenied},
		{"other owner first", []int64{otherFileID, missingID}, ente.ErrPermissionDenied},
		{"duplicate", []int64{fileID, fileID}, ente.ErrBadRequest},
	} {
		t.Run(tc.name, func(t *testing.T) {
			files := make([]ente.CollectionFileItem, 0, len(tc.ids))
			for _, id := range tc.ids {
				files = append(files, item(id))
			}
			if err := c.RestoreFiles(ctx, ownerID, collectionID, files); !errors.Is(err, tc.want) {
				t.Fatalf("RestoreFiles() error = %v, want %v", err, tc.want)
			}
			assertRestoredCount(t, 0)
		})
	}
	if err := c.RestoreFiles(ctx, ownerID, collectionID, []ente.CollectionFileItem{item(fileID), item(secondFileID)}); err != nil {
		t.Fatalf("RestoreFiles() error = %v", err)
	}
	assertRestoredCount(t, 2)
}
