package collections

import (
	"encoding/json"
	"errors"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/cast"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/controller/access"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
)

func TestFileDiffScrubsDeletedAndPendingFiles(t *testing.T) {
	db, collectionRepo, collectionOwnerID, viewerID := setupCollectionShareTest(t)
	collectionRepo.LatencyLogger = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{},
		[]string{"method"},
	)
	collectionID := createShareTestCollection(t, collectionRepo, collectionOwnerID)
	addShareTestShare(t, collectionRepo, collectionID, collectionOwnerID, viewerID, ente.VIEWER)
	activeFileID := addShareTestOwnerFile(t, db, collectionID, collectionOwnerID)
	deletedFileID := addShareTestOwnerFile(t, db, collectionID, collectionOwnerID)
	pendingFileID := addShareTestOwnerFile(t, db, collectionID, collectionOwnerID)
	if _, err := db.Exec(
		`UPDATE collection_files SET moderation_status = $1, anon_user_id = 'guest', updation_time = 2
		 WHERE collection_id = $2 AND file_id = $3`,
		ente.ModerationPending, collectionID, pendingFileID,
	); err != nil {
		t.Fatal(err)
	}

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
		 WHERE file_id IN ($1, $2)`,
		deletedFileID, pendingFileID,
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
				return controller.GetDiffV2(ctx, collectionID, viewerID, 0, true)
			},
		},
		{
			name: "owner",
			fetch: func() ([]ente.File, bool, error) {
				return controller.GetDiffV2(newBatchShareTestContext(collectionOwnerID), collectionID, collectionOwnerID, 0, false)
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

			for _, id := range []int64{deletedFileID, pendingFileID} {
				deleted := findFileDiffTestFile(t, files, id)
				if !deleted.IsDeleted || deleted.OwnerID != collectionOwnerID || deleted.CollectionID != collectionID || deleted.UpdationTime != 2 {
					t.Fatalf("invalid tombstone identity: %+v", deleted)
				}
				wantMetadata := ente.FileAttributes{EncryptedData: "-"}
				if deleted.EncryptedKey != "" || deleted.KeyDecryptionNonce != "" ||
					deleted.File != (ente.FileAttributes{}) || deleted.Thumbnail != (ente.FileAttributes{}) ||
					deleted.Metadata != wantMetadata || deleted.MagicMetadata != nil ||
					deleted.PublicMagicMetadata != nil || deleted.Info != nil ||
					deleted.ModerationStatus != nil || deleted.AnonUserID != nil || deleted.Action != nil || deleted.ActionUserID != nil {
					t.Fatalf("tombstone contents were returned: %+v", deleted)
				}
				assertFileDiffTestWireShape(t, deleted)
			}
		})
	}
}

func TestFileDiffReturnsPendingUploadsToModerators(t *testing.T) {
	db, collectionRepo, ownerID, viewerID := setupCollectionShareTest(t)
	collectionRepo.LatencyLogger = prometheus.NewHistogramVec(prometheus.HistogramOpts{}, []string{"method"})
	adminID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 3, Email: "admin@example.com", CreationTime: 1})
	collectionID := createShareTestCollection(t, collectionRepo, ownerID)
	addShareTestShare(t, collectionRepo, collectionID, ownerID, viewerID, ente.VIEWER)
	addShareTestShare(t, collectionRepo, collectionID, ownerID, adminID, ente.ADMIN)
	publishedFileID := addShareTestOwnerFile(t, db, collectionID, ownerID)
	pendingFileID := addShareTestOwnerFile(t, db, collectionID, ownerID)
	if _, err := db.Exec(
		`UPDATE collection_files SET moderation_status = $1, anon_user_id = 'guest' WHERE collection_id = $2 AND file_id = $3`,
		ente.ModerationPending, collectionID, pendingFileID,
	); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(
		`UPDATE files SET magic_metadata = '{"version":1,"count":1,"data":"private","header":"header"}'::jsonb WHERE file_id = $1`,
		pendingFileID,
	); err != nil {
		t.Fatal(err)
	}
	controller := &CollectionController{
		AccessCtrl:     access.NewAccessController(collectionRepo, nil),
		CollectionRepo: collectionRepo,
	}

	for _, tc := range []struct {
		name           string
		actor          int64
		includePending bool
		wantFull       bool
		wantMagic      bool
	}{
		{name: "owner with flag", actor: ownerID, includePending: true, wantFull: true, wantMagic: true},
		{name: "admin with flag", actor: adminID, includePending: true, wantFull: true},
		{name: "admin without flag", actor: adminID},
		{name: "viewer with flag", actor: viewerID, includePending: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ctx := newBatchShareTestContext(tc.actor)
			files, _, err := controller.GetDiffV2(ctx, collectionID, tc.actor, 0, tc.includePending)
			if err != nil {
				t.Fatal(err)
			}
			diffFile := findFileDiffTestFile(t, files, pendingFileID)
			file, err := controller.GetFile(ctx, collectionID, pendingFileID, tc.includePending)
			if !tc.wantFull {
				if !diffFile.IsDeleted || diffFile.EncryptedKey != "" || diffFile.ModerationStatus != nil || diffFile.AnonUserID != nil {
					t.Fatalf("pending upload was not a tombstone: %+v", diffFile)
				}
				if file != nil || !errors.Is(err, &ente.ErrFileNotFoundInAlbum) {
					t.Fatalf("pending file lookup = (%+v, %v), want file not found", file, err)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			for _, got := range []ente.File{diffFile, *file} {
				if got.IsDeleted || got.EncryptedKey != "collection-file-key" ||
					got.ModerationStatus == nil || *got.ModerationStatus != ente.ModerationPending ||
					got.AnonUserID == nil || *got.AnonUserID != "guest" || (got.MagicMetadata != nil) != tc.wantMagic {
					t.Fatalf("unexpected pending upload: %+v", got)
				}
			}
		})
	}
	t.Run("flag returns only pending rows to moderators", func(t *testing.T) {
		files, hasMore, err := controller.GetDiffV2(newBatchShareTestContext(adminID), collectionID, adminID, 0, true)
		if err != nil || hasMore || len(files) != 1 || files[0].ID != pendingFileID || files[0].IsDeleted {
			t.Fatalf("moderator diff = (%+v, %t, %v), want only file %d, not %d", files, hasMore, err, pendingFileID, publishedFileID)
		}
		files, _, err = controller.GetDiffV2(newBatchShareTestContext(viewerID), collectionID, viewerID, 0, true)
		if err != nil || findFileDiffTestFile(t, files, publishedFileID).IsDeleted {
			t.Fatalf("viewer diff with flag = (%+v, %v), want the normal diff", files, err)
		}
	})
}

func TestPublicDiffReturnsGuestOwnPendingUploads(t *testing.T) {
	db, collectionRepo, ownerID, _ := setupCollectionShareTest(t)
	collectionRepo.LatencyLogger = prometheus.NewHistogramVec(prometheus.HistogramOpts{}, []string{"method"})
	collectionID := createShareTestCollection(t, collectionRepo, ownerID)
	pendingFileID := addShareTestOwnerFile(t, db, collectionID, ownerID)
	if _, err := db.Exec(
		`UPDATE collection_files SET moderation_status = $1, anon_user_id = 'guest' WHERE collection_id = $2 AND file_id = $3`,
		ente.ModerationPending, collectionID, pendingFileID,
	); err != nil {
		t.Fatal(err)
	}
	controller := &CollectionController{CollectionRepo: collectionRepo}

	for _, tc := range []struct {
		name     string
		guestID  string
		wantFull bool
	}{
		{name: "uploading guest", guestID: "guest", wantFull: true},
		{name: "other guest", guestID: "other"},
		{name: "no identity"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ctx := newFileDiffTestContext("/public-collection/diff")
			ctx.Set(auth.PublicAccessKey, ente.PublicAccessContext{CollectionID: collectionID})
			if tc.guestID != "" {
				auth.SetPublicAnonUserID(ctx, tc.guestID)
			}
			files, _, err := controller.GetPublicDiff(ctx, 0)
			if err != nil {
				t.Fatal(err)
			}
			got := findFileDiffTestFile(t, files, pendingFileID)
			if !tc.wantFull {
				if !got.IsDeleted || got.EncryptedKey != "" || got.ModerationStatus != nil || got.AnonUserID != nil {
					t.Fatalf("pending upload was not a tombstone: %+v", got)
				}
				return
			}
			if got.IsDeleted || got.EncryptedKey != "collection-file-key" || got.MagicMetadata != nil ||
				got.ModerationStatus == nil || *got.ModerationStatus != ente.ModerationPending ||
				got.AnonUserID == nil || *got.AnonUserID != "guest" {
				t.Fatalf("unexpected pending upload: %+v", got)
			}
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
