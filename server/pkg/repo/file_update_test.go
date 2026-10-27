package repo

import (
	"database/sql"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/lib/pq"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

func TestUpdateFileReplicaLocations(t *testing.T) {
	viper.Reset()
	viper.Set("s3.hot_storage.primary", "b2-eu-cen")
	t.Cleanup(viper.Reset)
	s3Config := s3config.NewS3Config()

	for _, tc := range []struct {
		name           string
		metadata       string
		replaceObjects bool
	}{
		{name: "retry", metadata: "encrypted-metadata"},
		{name: "metadata update", metadata: "updated-metadata"},
		{name: "replacement", metadata: "updated-metadata", replaceObjects: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			db := setupFileUsageTest(t)
			ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
				UserID: 1, Email: "replica-update@example.com", CreationTime: 1,
			})
			testutil.InsertUsage(t, db, ownerID, 110)
			collectionID := insertObjectTestCollection(t, db, ownerID)
			fileID := insertObjectTestFile(t, db, ownerID)
			linkObjectTestFileToCollection(t, db, collectionID, fileID, ownerID)
			fileLocations := []string{"b2-eu-cen", "wasabi-eu-central-2-v3", "scw-eu-fr-v3"}
			thumbnailLocations := fileLocations[:2]
			insertObjectTestKey(t, db, fileID, ente.FILE, "replica-file", 100, fileLocations)
			insertObjectTestKey(t, db, fileID, ente.THUMBNAIL, "replica-thumbnail", 10, thumbnailLocations)
			_, err := db.Exec(`INSERT INTO object_copies
				(object_key, b2, want_b2, wasabi, want_wasabi, scw, want_scw)
				SELECT object_key, 1, TRUE, 2, TRUE, CASE WHEN o_type = 'file' THEN 3 END, o_type = 'file'
				FROM object_keys WHERE file_id = $1`, fileID)
			require.NoError(t, err)
			t.Cleanup(func() {
				_, err := db.Exec(`DELETE FROM queue WHERE queue_name = $1 AND item IN ('replica-file', 'replica-thumbnail')`, OutdatedObjectsQueue)
				require.NoError(t, err)
			})
			repository := &FileRepository{
				DB:                db,
				S3Config:          s3Config,
				QueueRepo:         &QueueRepository{DB: db},
				ObjectCleanupRepo: &ObjectCleanupRepository{DB: db},
				ObjectCopiesRepo:  &ObjectCopiesRepository{DB: db},
			}
			file := ente.File{
				ID: fileID, OwnerID: ownerID, CollectionID: collectionID, UpdationTime: 2,
				File:      ente.FileAttributes{ObjectKey: "replica-file", DecryptionHeader: "file-header"},
				Thumbnail: ente.FileAttributes{ObjectKey: "replica-thumbnail", DecryptionHeader: "thumbnail-header"},
				Metadata:  ente.FileAttributes{EncryptedData: tc.metadata, DecryptionHeader: "metadata-header"},
				Info:      &ente.FileInfo{FileSize: 100, ThumbnailSize: 10},
			}
			var oldObjects, stagedObjects []string
			var usageDiff int64
			if tc.replaceObjects {
				oldObjects = []string{file.File.ObjectKey, file.Thumbnail.ObjectKey}
				file.File.ObjectKey = "replacement-file"
				file.Thumbnail.ObjectKey = "replacement-thumbnail"
				file.Info.FileSize = 200
				file.Info.ThumbnailSize = 20
				usageDiff = 110
				stagedObjects = []string{file.File.ObjectKey, file.Thumbnail.ObjectKey}
				_, err := db.Exec(`INSERT INTO temp_objects (object_key, expiration_time)
					SELECT unnest($1::text[]), 1`, pq.Array(stagedObjects))
				require.NoError(t, err)
				fileLocations = []string{s3Config.GetHotDataCenter()}
				thumbnailLocations = fileLocations
			}

			require.NoError(t, repository.Update(file, file.Info.FileSize, file.Info.ThumbnailSize, usageDiff, oldObjects, stagedObjects, ente.Photos))
			for _, object := range []struct {
				kind      ente.ObjectType
				key       string
				size      int64
				locations []string
			}{
				{ente.FILE, file.File.ObjectKey, file.Info.FileSize, fileLocations},
				{ente.THUMBNAIL, file.Thumbnail.ObjectKey, file.Info.ThumbnailSize, thumbnailLocations},
			} {
				stored, locations, err := (&ObjectRepository{DB: db}).GetObjectWithDCs(fileID, object.kind)
				require.NoError(t, err)
				require.Equal(t, object.key, stored.ObjectKey)
				require.Equal(t, object.size, stored.FileSize)
				require.Equal(t, object.locations, locations, "%s replica locations", object.kind)
				var wasabi sql.NullInt64
				require.NoError(t, db.QueryRow(`SELECT wasabi FROM object_copies WHERE object_key = $1`, object.key).Scan(&wasabi))
				if tc.replaceObjects {
					require.False(t, wasabi.Valid, "replacement must be queued for replication")
				} else {
					require.Equal(t, sql.NullInt64{Int64: 2, Valid: true}, wasabi, "completed replication must remain unchanged")
				}
			}
			storedFile, err := repository.GetFileAttributes(fileID)
			require.NoError(t, err)
			require.Equal(t, file.Metadata, storedFile.Metadata)
			require.Equal(t, file.Info, storedFile.Info)
			var updatedAt int64
			require.NoError(t, db.QueryRow(`SELECT updation_time FROM collection_files WHERE collection_id = $1 AND file_id = $2`, collectionID, fileID).Scan(&updatedAt))
			require.Equal(t, file.UpdationTime, updatedAt)
		})
	}
}
