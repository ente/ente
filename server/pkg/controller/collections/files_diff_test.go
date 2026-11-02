package collections

import (
	"encoding/json"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/cast"
	"github.com/ente/museum/pkg/controller/access"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
)

func TestFileDiffScrubsDeletedFiles(t *testing.T) {
	db, collectionRepo, collectionOwnerID, viewerID := setupCollectionShareTest(t)
	collectionRepo.LatencyLogger = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{},
		[]string{"method"},
	)
	collectionID := createShareTestCollection(t, collectionRepo, collectionOwnerID)
	addShareTestShare(t, collectionRepo, collectionID, collectionOwnerID, viewerID, ente.VIEWER)
	activeFileID := addShareTestOwnerFile(t, db, collectionID, collectionOwnerID)
	deletedFileID := addShareTestOwnerFile(t, db, collectionID, collectionOwnerID)

	if _, err := db.Exec(
		`UPDATE collection_files SET is_deleted = TRUE, updation_time = 2
		 WHERE collection_id = $1 AND file_id = $2`,
		collectionID,
		deletedFileID,
	); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(
		`UPDATE files SET file_decryption_header = 'current-file-header',
			thumbnail_decryption_header = 'current-thumbnail-header',
			metadata_decryption_header = 'current-metadata-header',
			encrypted_metadata = 'current-encrypted-metadata',
			magic_metadata = '{"version":2,"count":1,"data":"current-private-metadata","header":"private-header"}'::jsonb,
			pub_magic_metadata = '{"version":2,"count":1,"data":"current-public-metadata","header":"public-header"}'::jsonb,
			info = '{"fileSize":123,"thumbSize":45}'::jsonb
		 WHERE file_id = $1`,
		deletedFileID,
	); err != nil {
		t.Fatal(err)
	}

	controller := &CollectionController{
		AccessCtrl:     access.NewAccessController(collectionRepo, nil),
		CollectionRepo: collectionRepo,
	}
	views := []struct {
		name  string
		fetch func() ([]ente.File, bool, error)
	}{
		{
			name: "authenticated",
			fetch: func() ([]ente.File, bool, error) {
				ctx := newFileDiffTestContext("/collections/v2/diff")
				ctx.Request.Header.Set("X-Auth-User-ID", strconv.FormatInt(viewerID, 10))
				return controller.GetDiffV2(ctx, collectionID, viewerID, 0)
			},
		},
		{
			name: "public",
			fetch: func() ([]ente.File, bool, error) {
				ctx := newFileDiffTestContext("/public-collection/diff")
				ctx.Set(auth.PublicAccessKey, ente.PublicAccessContext{CollectionID: collectionID})
				return controller.GetPublicDiff(ctx, 0)
			},
		},
		{
			name: "cast",
			fetch: func() ([]ente.File, bool, error) {
				ctx := newFileDiffTestContext("/cast/diff")
				ctx.Set(auth.CastContext, cast.AuthContext{CollectionID: collectionID})
				return controller.GetCastDiff(ctx, 0)
			},
		},
	}

	for _, view := range views {
		t.Run(view.name, func(t *testing.T) {
			files, hasMore, err := view.fetch()
			if err != nil {
				t.Fatal(err)
			}
			if hasMore {
				t.Fatal("unexpected additional diff page")
			}

			active := findFileDiffTestFile(t, files, activeFileID)
			if active.EncryptedKey != "collection-file-key" || active.Metadata.EncryptedData != "encrypted-metadata" {
				t.Fatalf("active file was scrubbed: %+v", active)
			}

			deleted := findFileDiffTestFile(t, files, deletedFileID)
			if !deleted.IsDeleted || deleted.OwnerID != collectionOwnerID || deleted.CollectionID != collectionID || deleted.UpdationTime != 2 {
				t.Fatalf("invalid tombstone identity: %+v", deleted)
			}
			wantMetadata := ente.FileAttributes{EncryptedData: "-"}
			if deleted.EncryptedKey != "" || deleted.KeyDecryptionNonce != "" ||
				deleted.File != (ente.FileAttributes{}) || deleted.Thumbnail != (ente.FileAttributes{}) ||
				deleted.Metadata != wantMetadata || deleted.MagicMetadata != nil ||
				deleted.PublicMagicMetadata != nil || deleted.Info != nil {
				t.Fatalf("deleted file contents were returned: %+v", deleted)
			}
			assertFileDiffTestWireShape(t, deleted)
		})
	}
}

func newFileDiffTestContext(path string) *gin.Context {
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	ctx.Request = httptest.NewRequest("GET", path, nil)
	return ctx
}

func findFileDiffTestFile(t *testing.T, files []ente.File, fileID int64) ente.File {
	t.Helper()
	for _, file := range files {
		if file.ID == fileID {
			return file
		}
	}
	t.Fatalf("file %d not found in diff", fileID)
	return ente.File{}
}

func assertFileDiffTestWireShape(t *testing.T, file ente.File) {
	t.Helper()
	encoded, err := json.Marshal(file)
	if err != nil {
		t.Fatal(err)
	}
	var response map[string]json.RawMessage
	if err := json.Unmarshal(encoded, &response); err != nil {
		t.Fatal(err)
	}
	var metadata map[string]json.RawMessage
	if err := json.Unmarshal(response["metadata"], &metadata); err != nil {
		t.Fatal(err)
	}
	var encryptedData string
	if err := json.Unmarshal(metadata["encryptedData"], &encryptedData); err != nil {
		t.Fatal(err)
	}
	if encryptedData != "-" {
		t.Fatalf("metadata encryptedData = %q, want tombstone marker", encryptedData)
	}
	var decryptionHeader string
	if err := json.Unmarshal(metadata["decryptionHeader"], &decryptionHeader); err != nil {
		t.Fatal(err)
	}
	if decryptionHeader != "" {
		t.Fatalf("metadata decryptionHeader = %q, want empty", decryptionHeader)
	}
}
