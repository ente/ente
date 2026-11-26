package controller

import (
	"database/sql"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/config"
	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

func TestFileRegistrationStoresApp(t *testing.T) {
	_, fileRepo, db := setupObjectCleanupRaceTest(t, "http://127.0.0.1")
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "file-app-owner@ente.com",
		CreationTime: 1,
	})
	testutil.InsertUsage(t, db, ownerID, 0)
	collectionID := insertObjectCleanupTestCollection(t, db, ownerID)
	const fileObjectKey = "1/file-app-file"
	const thumbnailObjectKey = "1/file-app-thumbnail"
	if _, err := db.Exec(`
		INSERT INTO temp_objects(object_key, expiration_time, bucket_id)
		VALUES ($1, 0, 'b2-eu-cen'), ($2, 0, 'b2-eu-cen')`, fileObjectKey, thumbnailObjectKey); err != nil {
		t.Fatalf("failed to stage objects: %v", err)
	}

	file, _, err := fileRepo.Create(objectCleanupTestFile(
		ownerID, collectionID, fileObjectKey, thumbnailObjectKey,
	), 100, 10, 110, ownerID, ente.Photos, repo.FileObjectBuckets{File: "b2-eu-cen", Thumbnail: "b2-eu-cen"})
	if err != nil {
		t.Fatal(err)
	}

	var app string
	if err := db.QueryRow(`SELECT app FROM files WHERE file_id = $1`, file.ID).Scan(&app); err != nil {
		t.Fatal(err)
	}
	if app != string(ente.Photos) {
		t.Fatalf("file app = %q, want %q", app, ente.Photos)
	}
}

func TestFileRegistrationRollsBackWhenCleanupWins(t *testing.T) {
	cleanupDeleting := make(chan struct{})
	releaseCleanup := make(chan struct{})
	var blockCleanup sync.Once
	s3Server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodDelete:
			blockCleanup.Do(func() {
				close(cleanupDeleting)
				<-releaseCleanup
			})
			w.WriteHeader(http.StatusNoContent)
		case http.MethodHead:
			w.WriteHeader(http.StatusNotFound)
		default:
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	}))
	t.Cleanup(s3Server.Close)
	var releaseOnce sync.Once
	release := func() { releaseOnce.Do(func() { close(releaseCleanup) }) }

	cleanupController, fileRepo, db := setupObjectCleanupRaceTest(t, s3Server.URL)
	cleanupPool, err := sql.Open("postgres", "sslmode=disable")
	if err != nil {
		t.Fatalf("failed to open cleanup pool: %v", err)
	}
	cleanupPool.SetMaxOpenConns(1)
	t.Cleanup(func() { _ = cleanupPool.Close() })
	cleanupController.Repo = &repo.ObjectCleanupRepository{DB: cleanupPool}
	cleanupController.ObjectRepo = &repo.ObjectRepository{DB: cleanupPool}
	t.Cleanup(release)
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "cleanup-race-owner@ente.com",
		CreationTime: 1,
	})
	collectionID := insertObjectCleanupTestCollection(t, db, ownerID)
	const fileObjectKey = "1/cleanup-race-file"
	const thumbnailObjectKey = "1/cleanup-race-thumbnail"
	if _, err := db.Exec(`
		INSERT INTO temp_objects(object_key, expiration_time, bucket_id)
		VALUES ($1, 0, 'b2-eu-cen'), ($2, 0, 'b2-eu-cen')`, fileObjectKey, thumbnailObjectKey); err != nil {
		t.Fatalf("failed to stage objects: %v", err)
	}

	cleanupDone := make(chan int, 1)
	go func() { cleanupDone <- cleanupController.removeUnreportedObjects() }()
	select {
	case <-cleanupDeleting:
	case <-time.After(2 * time.Second):
		t.Fatal("cleanup did not reach object deletion")
	}

	if inUse := cleanupPool.Stats().InUse; inUse != 0 {
		t.Fatalf("cleanup held %d DB connection(s) open during S3 deletion", inUse)
	}

	registrationDone := make(chan error, 1)
	go func() {
		_, _, err := fileRepo.Create(objectCleanupTestFile(
			ownerID, collectionID, fileObjectKey, thumbnailObjectKey,
		), 100, 10, 110, ownerID, ente.Photos, repo.FileObjectBuckets{File: "b2-eu-cen", Thumbnail: "b2-eu-cen"})
		registrationDone <- err
	}()
	select {
	case err := <-registrationDone:
		var apiErr *ente.ApiError
		if !errors.As(err, &apiErr) || apiErr.Message != "staged upload not found" {
			t.Fatalf("registration error = %v, want staged upload not found", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("registration blocked while cleanup was deleting from S3")
	}
	release()

	select {
	case count := <-cleanupDone:
		if count != 2 {
			t.Fatalf("cleanup removed %d objects, want 2", count)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("cleanup did not finish")
	}

	var files, objectKeys, collectionFiles, tempObjects int
	if err := db.QueryRow(`SELECT
		(SELECT COUNT(*) FROM files WHERE owner_id = $1),
		(SELECT COUNT(*) FROM object_keys WHERE object_key IN ($2, $3)),
		(SELECT COUNT(*) FROM collection_files WHERE collection_id = $4),
		(SELECT COUNT(*) FROM temp_objects WHERE object_key IN ($2, $3))`,
		ownerID, fileObjectKey, thumbnailObjectKey, collectionID,
	).Scan(&files, &objectKeys, &collectionFiles, &tempObjects); err != nil {
		t.Fatalf("failed to read registration state: %v", err)
	}
	if files != 0 || objectKeys != 0 || collectionFiles != 0 || tempObjects != 0 {
		t.Fatalf("unexpected registration state: files=%d object_keys=%d collection_files=%d temp_objects=%d",
			files, objectKeys, collectionFiles, tempObjects)
	}
}

func TestB2TempCleanupMultipartRetry(t *testing.T) {
	var failAbort atomic.Bool
	failAbort.Store(true)
	var aborts, deletes atomic.Int32
	s3Server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/xml")
		switch {
		case r.Method == http.MethodDelete && r.URL.Query().Has("uploadId"):
			aborts.Add(1)
			if failAbort.Load() {
				w.WriteHeader(http.StatusForbidden)
				_, _ = io.WriteString(w, `<Error><Code>AccessDenied</Code></Error>`)
				return
			}
			w.WriteHeader(http.StatusNoContent)
		case r.Method == http.MethodGet && r.URL.Query().Has("uploadId"):
			w.WriteHeader(http.StatusNotFound)
			_, _ = io.WriteString(w, `<Error><Code>NoSuchUpload</Code></Error>`)
		case r.Method == http.MethodDelete:
			deletes.Add(1)
			w.WriteHeader(http.StatusNoContent)
		case r.Method == http.MethodHead:
			w.WriteHeader(http.StatusNotFound)
		default:
			t.Errorf("unexpected request: %s %s", r.Method, r.URL)
			w.WriteHeader(http.StatusBadRequest)
		}
	}))
	t.Cleanup(s3Server.Close)

	c, _, db := setupObjectCleanupRaceTest(t, s3Server.URL)
	_, err := db.Exec(`INSERT INTO temp_objects(object_key, expiration_time, bucket_id, is_multipart, upload_id)
		VALUES ('1/b2-multipart', 0, 'b2-eu-cen', TRUE, 'upload-id')`)
	require.NoError(t, err)

	require.Zero(t, c.removeUnreportedObjects())
	require.EqualValues(t, 1, aborts.Load())
	require.Zero(t, deletes.Load())

	var cleanupState string
	var delayed bool
	require.NoError(t, db.QueryRow(`SELECT COALESCE(cleanup_state, ''), expiration_time > now_utc_micro_seconds()
		FROM temp_objects WHERE object_key = '1/b2-multipart'`).Scan(&cleanupState, &delayed))
	require.Equal(t, string(ente.TempObjectDirectDelete), cleanupState)
	require.True(t, delayed)

	_, err = c.Repo.GetFileUploadBucket(t.Context(), "1/b2-multipart", 1, ente.Photos)
	require.ErrorIs(t, err, sql.ErrNoRows)

	failAbort.Store(false)
	_, err = db.Exec(`UPDATE temp_objects SET expiration_time = 0 WHERE object_key = '1/b2-multipart'`)
	require.NoError(t, err)

	require.Equal(t, 1, c.removeUnreportedObjects())
	require.EqualValues(t, 2, aborts.Load())
	require.EqualValues(t, 1, deletes.Load())

	var remaining int
	require.NoError(t, db.QueryRow(`SELECT count(*) FROM temp_objects`).Scan(&remaining))
	require.Zero(t, remaining)
}

func waitForTempObjectDeleteLock(t *testing.T, db *sql.DB) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for {
		var waiting bool
		err := db.QueryRow(`SELECT EXISTS(
			SELECT 1 FROM pg_stat_activity
			WHERE datname = current_database()
			  AND pid <> pg_backend_pid()
			  AND wait_event_type = 'Lock'
			  AND query LIKE '%DELETE FROM temp_objects%'
		)`).Scan(&waiting)
		if err != nil {
			t.Fatalf("failed to inspect registration lock wait: %v", err)
		}
		if waiting {
			return
		}
		if time.Now().After(deadline) {
			t.Fatal("registration did not wait for the temporary-object lock")
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func setupObjectCleanupRaceTest(t *testing.T, endpoint string) (*ObjectCleanupController, *repo.FileRepository, *sql.DB) {
	t.Helper()
	testutil.WithServerRoot(t)
	viper.Reset()
	if err := config.ConfigureViper("local"); err != nil {
		t.Fatal(err)
	}
	viper.Set("s3.b2-eu-cen.key", "test-key")
	viper.Set("s3.b2-eu-cen.secret", "test-secret")
	viper.Set("s3.b2-eu-cen.endpoint", endpoint)
	viper.Set("s3.b2-eu-cen.region", "us-east-1")
	viper.Set("s3.b2-eu-cen.bucket", "test-bucket")
	viper.Set("s3.b2-eu-cen.disable_ssl", true)
	viper.Set("s3.use_path_style_urls", true)
	t.Cleanup(viper.Reset)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	s3Config := s3config.NewS3Config()
	objectRepo := &repo.ObjectRepository{DB: db}
	objectCleanupRepo := &repo.ObjectCleanupRepository{DB: db}
	return NewObjectCleanupController(objectCleanupRepo, objectRepo, s3Config), &repo.FileRepository{
		DB:                db,
		S3Config:          s3Config,
		QueueRepo:         &repo.QueueRepository{DB: db},
		ObjectRepo:        objectRepo,
		ObjectCleanupRepo: objectCleanupRepo,
		ObjectCopiesRepo:  &repo.ObjectCopiesRepository{DB: db},
	}, db
}

func insertObjectCleanupTestCollection(t *testing.T, db *sql.DB, ownerID int64) int64 {
	t.Helper()
	var collectionID int64
	err := db.QueryRow(`
		INSERT INTO collections(owner_id, encrypted_key, key_decryption_nonce, name, type, attributes, updation_time, app)
		VALUES($1, 'encrypted-key', 'key-nonce', 'Cleanup race', 'album', '{}', 1, 'photos')
		RETURNING collection_id`, ownerID).Scan(&collectionID)
	if err != nil {
		t.Fatalf("failed to insert collection: %v", err)
	}
	return collectionID
}

func objectCleanupTestFile(ownerID, collectionID int64, fileObjectKey, thumbnailObjectKey string) ente.File {
	return ente.File{
		OwnerID:            ownerID,
		CollectionID:       collectionID,
		EncryptedKey:       "encrypted-key",
		KeyDecryptionNonce: "key-nonce",
		File: ente.FileAttributes{
			ObjectKey:        fileObjectKey,
			DecryptionHeader: "file-header",
		},
		Thumbnail: ente.FileAttributes{
			ObjectKey:        thumbnailObjectKey,
			DecryptionHeader: "thumbnail-header",
		},
		Metadata: ente.FileAttributes{
			EncryptedData:    "encrypted-metadata",
			DecryptionHeader: "metadata-header",
		},
		UpdationTime: 1,
		Info:         &ente.FileInfo{FileSize: 100, ThumbnailSize: 10},
	}
}
