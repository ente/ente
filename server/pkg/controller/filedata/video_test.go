package filedata

import (
	"database/sql"
	"fmt"
	"testing"

	"github.com/ente/museum/ente"
	enteFileData "github.com/ente/museum/ente/filedata"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	log "github.com/sirupsen/logrus"
	logtest "github.com/sirupsen/logrus/hooks/test"
	"github.com/stretchr/testify/require"
)

func TestObserveVideoPreviewSizeUsesStoredOriginal(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID: 1, Email: "preview-size@example.com", CreationTime: 1,
	})
	c := &Controller{FileRepo: &repo.FileRepository{DB: db}}
	for _, tc := range []struct {
		name         string
		info         any
		originalSize int64
		previewSize  int64
		onlyThumb    bool
		warning      string
	}{
		{"stored size within limit", `{"fileSize":50000000}`, 0, 190_000_000, false, ""},
		{"stored size above limit", `{"fileSize":50000000}`, 0, 200_000_000, false, "video preview exceeds size limit"},
		{"legacy original below 4x", nil, 40_000_000, 159_999_999, false, ""},
		{"legacy original at 4x", nil, 40_000_000, 160_000_000, false, "video preview exceeds size limit"},
		{"zero metadata falls back", `{"fileSize":0}`, 40_000_000, 159_999_999, false, ""},
		{"no original size", nil, 0, 1, false, "video preview size check missing original size"},
		{"thumbnail is not original", nil, 500_000_000, 1, true, "video preview size check missing original size"},
		{"stored original takes precedence", `{"fileSize":50000000}`, 500_000_000, 200_000_000, false, "video preview exceeds size limit"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var fileID int64
			require.NoError(t, db.QueryRow(`INSERT INTO files
				(owner_id, file_decryption_header, thumbnail_decryption_header,
				 metadata_decryption_header, encrypted_metadata, updation_time, info)
				VALUES ($1, 'file-header', 'thumb-header', 'metadata-header', 'metadata', 1, $2::jsonb)
				RETURNING file_id`, ownerID, tc.info).Scan(&fileID))
			if tc.originalSize > 0 {
				kind := ente.FILE
				if tc.onlyThumb {
					kind = ente.THUMBNAIL
				}
				_, err := db.Exec(`INSERT INTO object_keys (file_id, o_type, object_key, size, datacenters)
					VALUES ($1, $2, $3, $4, ARRAY['b2-eu-cen']::s3region[])`,
					fileID, kind, fmt.Sprintf("preview-original-%d", fileID), tc.originalSize)
				require.NoError(t, err)
			}
			logger, hook := logtest.NewNullLogger()
			c.observeVideoPreviewSize(t.Context(), &enteFileData.VidPreviewRequest{
				FileID: fileID, ObjectSize: tc.previewSize,
			}, ownerID, log.NewEntry(logger))
			if tc.warning == "" {
				require.Empty(t, hook.AllEntries())
			} else {
				require.Len(t, hook.AllEntries(), 1)
				entry := hook.LastEntry()
				require.Equal(t, log.WarnLevel, entry.Level)
				require.Equal(t, tc.warning, entry.Message)
				require.Equal(t, fileID, entry.Data["file_id"])
				require.Equal(t, ownerID, entry.Data["user_id"])
				require.Equal(t, tc.previewSize, entry.Data["preview_size_bytes"])
				require.Equal(t, false, entry.Data["size_limit_enforced"])
			}
		})
	}
}

func TestWarnVideoPreviewSize(t *testing.T) {
	for _, tc := range []struct {
		name     string
		original int64
		preview  int64
		warning  string
	}{
		{"small expansion within limit", 50_000_000, 190_000_000, ""},
		{"small preview at 4x", 40_000_000, 160_000_000, "video preview exceeds size limit"},
		{"200 MB cutoff", 60_000_000, 200_000_000, "video preview exceeds size limit"},
		{"large preview at 3x", 100_000_000, 300_000_000, ""},
		{"large preview above 3x", 100_000_000, 300_000_001, "video preview exceeds size limit"},
		{"unknown original", 0, 1, "video preview size check missing original size"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			logger, hook := logtest.NewNullLogger()
			warnVideoPreviewSize(log.NewEntry(logger).WithFields(log.Fields{
				"req_id": "preview-size-request", "user_id": int64(42),
				"size_check_stage": "registration", "preview_size_source": "verified",
			}), &enteFileData.VidPreviewRequest{FileID: 7, ObjectSize: tc.preview}, tc.original)
			if tc.warning == "" {
				require.Empty(t, hook.AllEntries())
				return
			}
			require.Len(t, hook.AllEntries(), 1)
			entry := hook.LastEntry()
			require.Equal(t, log.WarnLevel, entry.Level)
			require.Equal(t, tc.warning, entry.Message)
			require.Equal(t, "preview-size-request", entry.Data["req_id"])
			require.Equal(t, "registration", entry.Data["size_check_stage"])
			require.Equal(t, "verified", entry.Data["preview_size_source"])
			require.Equal(t, int64(42), entry.Data["user_id"])
			require.Equal(t, int64(7), entry.Data["file_id"])
			require.Equal(t, tc.original, entry.Data["original_size_bytes"])
			require.Equal(t, tc.preview, entry.Data["preview_size_bytes"])
			require.Equal(t, false, entry.Data["size_limit_enforced"])
			if tc.original > 0 {
				require.Equal(t, float64(tc.preview)/float64(tc.original), entry.Data["preview_original_ratio"])
			} else {
				require.NotContains(t, entry.Data, "preview_original_ratio")
			}
		})
	}
}

func TestObserveVideoPreviewSizeLookupFailureOnlyWarns(t *testing.T) {
	db, err := sql.Open("postgres", "")
	require.NoError(t, err)
	require.NoError(t, db.Close())
	logger, hook := logtest.NewNullLogger()
	c := &Controller{FileRepo: &repo.FileRepository{DB: db}}
	c.observeVideoPreviewSize(t.Context(), &enteFileData.VidPreviewRequest{
		FileID: 7, ObjectSize: 200_000_000,
	}, 42, log.NewEntry(logger).WithFields(log.Fields{
		"req_id": "preview-size-request", "size_check_stage": "upload_url", "preview_size_source": "declared",
	}))
	require.Len(t, hook.AllEntries(), 1)
	entry := hook.LastEntry()
	require.Equal(t, log.WarnLevel, entry.Level)
	require.Equal(t, "could not check video preview size limit", entry.Message)
	require.Equal(t, "preview-size-request", entry.Data["req_id"])
	require.Equal(t, "upload_url", entry.Data["size_check_stage"])
	require.Equal(t, "declared", entry.Data["preview_size_source"])
	require.Equal(t, int64(42), entry.Data["user_id"])
	require.Equal(t, int64(7), entry.Data["file_id"])
	require.Equal(t, int64(200_000_000), entry.Data["preview_size_bytes"])
	require.Equal(t, false, entry.Data["size_limit_enforced"])
}
