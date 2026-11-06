package controller

import (
	"database/sql"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const cleanupWasabiDC = "wasabi-eu-central-2-v3"

func TestWasabiTempCleanupLifecycle(t *testing.T) {
	for _, multipart := range []bool{false, true} {
		name := "single part"
		if multipart {
			name = "multipart"
		}
		t.Run(name, func(t *testing.T) {
			var holds, deletes, aborts, lists atomic.Int32
			c, _, db := setupWasabiTempCleanupTest(t, func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/xml")
				if r.URL.Path == "/test-bucket/1/b2-expired" {
					w.WriteHeader(http.StatusForbidden)
					_, _ = io.WriteString(w, `<Error><Code>AccessDenied</Code></Error>`)
					return
				}
				assert.Equal(t, "/wasabi-bucket/1/expired", r.URL.Path)
				switch {
				case r.Method == http.MethodDelete && r.URL.Query().Has("uploadId"):
					aborts.Add(1)
					w.WriteHeader(http.StatusNoContent)
				case r.Method == http.MethodGet && r.URL.Query().Has("uploadId"):
					lists.Add(1)
					w.WriteHeader(http.StatusNotFound)
					_, _ = io.WriteString(w, `<Error><Code>NoSuchUpload</Code></Error>`)
				case r.Method == http.MethodPut && r.URL.Query().Has("compliance"):
					holds.Add(1)
					body, err := io.ReadAll(r.Body)
					assert.NoError(t, err)
					assert.Contains(t, string(body), "<ConditionalHold>false</ConditionalHold>")
				case r.Method == http.MethodDelete:
					deletes.Add(1)
					w.WriteHeader(http.StatusNoContent)
				case r.Method == http.MethodHead:
					w.WriteHeader(http.StatusNotFound)
				default:
					t.Errorf("unexpected request: %s %s", r.Method, r.URL)
					w.WriteHeader(http.StatusBadRequest)
				}
			})

			_, err := db.Exec(`INSERT INTO temp_objects(object_key, expiration_time, bucket_id, is_multipart, upload_id)
				VALUES ('1/expired', 0, $1, $2, 'upload-id')`, cleanupWasabiDC, multipart)
			require.NoError(t, err)
			_, err = db.Exec(`INSERT INTO temp_objects(object_key, expiration_time, bucket_id) VALUES ('1/b2-expired', 0, 'b2-eu-cen')`)
			require.NoError(t, err)
			require.Equal(t, 1, c.removeUnreportedObjects())
			require.EqualValues(t, 0, holds.Load())
			require.EqualValues(t, 0, deletes.Load())
			require.Zero(t, aborts.Load())
			require.Zero(t, lists.Load())
			assertTempCleanupState(t, db, "1/expired", ente.TempObjectReleaseHold)
			assertCleanupRowCount(t, db, `SELECT count(*) FROM temp_objects WHERE object_key = '1/b2-expired' AND expiration_time > now_utc_micro_seconds()`, 1)
			_, err = c.Repo.GetFileUploadBucket(t.Context(), "1/expired", 1, ente.Photos)
			require.ErrorIs(t, err, sql.ErrNoRows)

			tx, err := db.Begin()
			require.NoError(t, err)
			require.ErrorContains(t, c.Repo.ConsumeFileUpload(t.Context(), tx, "1/expired", 1, ente.Photos, cleanupWasabiDC), "staged upload not found")
			require.NoError(t, tx.Rollback())
			_, err = db.Exec(`UPDATE temp_objects SET expiration_time = 0 WHERE object_key = '1/expired'`)
			require.NoError(t, err)
			require.Equal(t, 1, c.removeUnreportedObjects())
			require.EqualValues(t, 1, holds.Load())
			assertTempCleanupState(t, db, "1/expired", ente.TempObjectDelete)
			assertCleanupRowCount(t, db, `SELECT count(*) FROM temp_objects WHERE object_key = '1/expired'
				AND expiration_time BETWEEN now_utc_micro_seconds() + (23::bigint * 86400000000)
				AND now_utc_micro_seconds() + (25::bigint * 86400000000)`, 1)
			if multipart {
				require.EqualValues(t, 1, aborts.Load())
				require.EqualValues(t, 1, lists.Load())
			}
			require.Equal(t, 0, c.removeUnreportedObjects())
			require.EqualValues(t, 0, deletes.Load())
			_, err = db.Exec(`UPDATE temp_objects SET expiration_time = 0 WHERE object_key = '1/expired'`)
			require.NoError(t, err)
			require.Equal(t, 1, c.removeUnreportedObjects())
			require.EqualValues(t, 1, deletes.Load())
			assertCleanupRowCount(t, db, `SELECT count(*) FROM temp_objects WHERE object_key = '1/expired'`, 0)
		})
	}
}

func TestWasabiTempCleanupMultipart(t *testing.T) {
	for _, outcome := range []string{"completed", "abort failed", "parts remain"} {
		t.Run(outcome, func(t *testing.T) {
			c, _, db := setupWasabiTempCleanupTest(t, func(w http.ResponseWriter, r *http.Request) {
				assert.Equal(t, "/wasabi-bucket/1/expired", r.URL.Path)
				if r.Method == http.MethodPut && r.URL.Query().Has("compliance") {
					assert.Equal(t, "completed", outcome)
					return
				}
				assert.Equal(t, "upload-id", r.URL.Query().Get("uploadId"))
				w.Header().Set("Content-Type", "application/xml")
				switch {
				case outcome == "completed":
					w.WriteHeader(http.StatusNotFound)
					_, _ = io.WriteString(w, `<Error><Code>NoSuchUpload</Code></Error>`)
				case outcome == "abort failed":
					w.WriteHeader(http.StatusForbidden)
					_, _ = io.WriteString(w, `<Error><Code>AccessDenied</Code></Error>`)
				case r.Method == http.MethodDelete:
					w.WriteHeader(http.StatusNoContent)
				case r.Method == http.MethodGet:
					_, _ = io.WriteString(w, `<ListPartsResult><Part><PartNumber>1</PartNumber></Part></ListPartsResult>`)
				default:
					t.Errorf("unexpected request: %s %s", r.Method, r.URL)
					w.WriteHeader(http.StatusBadRequest)
				}
			})
			require.NoError(t, c.Repo.AddTempObject(ente.TempObject{
				ObjectKey: "1/expired", BucketId: cleanupWasabiDC, IsMultipart: true, UploadID: "upload-id",
			}, 0))
			require.Equal(t, 1, c.removeUnreportedObjects())
			wantCount := 0
			if outcome == "completed" {
				wantCount = 1
			}
			require.Equal(t, wantCount, c.removeUnreportedObjects())
			wantState := ente.TempObjectReleaseHold
			if outcome == "completed" {
				wantState = ente.TempObjectDelete
			}
			assertTempCleanupState(t, db, "1/expired", wantState)
			assertCleanupRowCount(t, db, `SELECT count(*) FROM temp_objects WHERE expiration_time > now_utc_micro_seconds()`, 1)
		})
	}
}

func TestWasabiTempCleanupRouting(t *testing.T) {
	for _, tc := range []struct {
		name       string
		bucket     interface{}
		compliance bool
		wantBucket string
	}{
		{name: "B2 after switching primary", bucket: "b2-eu-cen", compliance: true, wantBucket: "test-bucket"},
		{name: "Wasabi without compliance", bucket: cleanupWasabiDC, wantBucket: "wasabi-bucket"},
		{name: "missing bucket", bucket: nil, compliance: true},
		{name: "unconfigured bucket", bucket: "b6", compliance: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var deletes atomic.Int32
			c, _, db := setupWasabiTempCleanupTest(t, func(w http.ResponseWriter, r *http.Request) {
				assert.NotEmpty(t, tc.wantBucket)
				assert.Equal(t, "/"+tc.wantBucket+"/1/expired", r.URL.Path)
				switch r.Method {
				case http.MethodDelete:
					deletes.Add(1)
					w.WriteHeader(http.StatusNoContent)
				case http.MethodHead:
					w.WriteHeader(http.StatusNotFound)
				default:
					t.Errorf("unexpected request: %s %s", r.Method, r.URL)
					w.WriteHeader(http.StatusBadRequest)
				}
			})
			viper.Set("s3."+cleanupWasabiDC+".compliance", tc.compliance)
			c.S3Config = s3config.NewS3Config()
			_, err := db.Exec(`INSERT INTO temp_objects(object_key, expiration_time, bucket_id) VALUES ('1/expired', 0, $1)`, tc.bucket)
			require.NoError(t, err)
			wantCount := 0
			if tc.wantBucket != "" {
				wantCount = 1
			}
			require.Equal(t, wantCount, c.removeUnreportedObjects())
			require.EqualValues(t, wantCount, deletes.Load())
			assertCleanupRowCount(t, db, `SELECT count(*) FROM temp_objects WHERE expiration_time > now_utc_micro_seconds()`, 1-wantCount)
			assertCleanupRowCount(t, db, `SELECT count(*) FROM temp_objects`, 1-wantCount)
		})
	}
}

func TestWasabiTempCleanupRetries(t *testing.T) {
	for _, state := range []ente.TempObjectCleanupState{ente.TempObjectReleaseHold, ente.TempObjectDelete} {
		for _, failure := range []string{"provider error", "missing object"} {
			t.Run(string(state)+"/"+failure, func(t *testing.T) {
				var calls atomic.Int32
				c, _, db := setupWasabiTempCleanupTest(t, func(w http.ResponseWriter, r *http.Request) {
					calls.Add(1)
					assert.True(t, strings.HasPrefix(r.URL.Path, "/wasabi-bucket/"))
					w.Header().Set("Content-Type", "application/xml")
					if failure == "provider error" {
						w.WriteHeader(http.StatusForbidden)
						_, _ = io.WriteString(w, `<Error><Code>AccessDenied</Code></Error>`)
					} else if r.Method == http.MethodDelete {
						w.WriteHeader(http.StatusNoContent)
					} else {
						w.WriteHeader(http.StatusNotFound)
						_, _ = io.WriteString(w, `<Error><Code>NoSuchKey</Code></Error>`)
					}
				})
				_, err := db.Exec(`INSERT INTO temp_objects(object_key, bucket_id, expiration_time, cleanup_state)
					VALUES ('1/expired', $1, 0, NULLIF($2, ''))`, cleanupWasabiDC, state)
				require.NoError(t, err)
				wantCount := 0
				if failure == "missing object" {
					wantCount = 1
				}
				require.Equal(t, wantCount, c.removeUnreportedObjects())
				previousCalls := calls.Load()
				require.Positive(t, previousCalls)
				require.Zero(t, c.removeUnreportedObjects())
				require.Equal(t, previousCalls, calls.Load())
				if failure == "provider error" {
					assertTempCleanupState(t, db, "1/expired", state)
					_, err = db.Exec(`UPDATE temp_objects SET expiration_time = expiration_time - (2::bigint * 86400000000)`)
					require.NoError(t, err)
					tx, objects, err := c.Repo.GetAndLockExpiredObjects()
					require.NoError(t, err)
					require.Len(t, objects, 1)
					require.NoError(t, tx.Rollback())
				} else if state == ente.TempObjectReleaseHold {
					assertTempCleanupState(t, db, "1/expired", ente.TempObjectDelete)
				} else {
					assertCleanupRowCount(t, db, `SELECT count(*) FROM temp_objects`, 0)
				}
			})
		}
	}
}

func TestWasabiTempCleanupRollback(t *testing.T) {
	for _, state := range []ente.TempObjectCleanupState{ente.TempObjectUploading, ente.TempObjectReleaseHold} {
		t.Run(string(state), func(t *testing.T) {
			var holds atomic.Int32
			c, _, db := setupWasabiTempCleanupTest(t, func(w http.ResponseWriter, r *http.Request) {
				assert.Equal(t, http.MethodPut, r.Method)
				assert.True(t, r.URL.Query().Has("compliance"))
				holds.Add(1)
			})
			_, err := db.Exec(`INSERT INTO temp_objects(object_key, bucket_id, expiration_time, cleanup_state)
				VALUES ('1/expired', $1, 0, NULLIF($2, ''))`, cleanupWasabiDC, state)
			require.NoError(t, err)
			if state == ente.TempObjectReleaseHold {
				viper.Set("s3."+cleanupWasabiDC+".compliance", false)
				c.S3Config = s3config.NewS3Config()
			}
			tx, objects, err := c.Repo.GetAndLockExpiredObjects()
			require.NoError(t, err)
			require.Len(t, objects, 1)
			require.Zero(t, c.removeUnreportedObjects())
			require.NoError(t, c.removeUnreportedObject(tx, objects[0]))
			require.NoError(t, tx.Rollback())
			assertTempCleanupState(t, db, "1/expired", state)
			require.Equal(t, 1, c.removeUnreportedObjects())
			if state == ente.TempObjectUploading {
				require.Zero(t, holds.Load())
				assertTempCleanupState(t, db, "1/expired", ente.TempObjectReleaseHold)
			} else {
				require.EqualValues(t, 2, holds.Load())
				assertTempCleanupState(t, db, "1/expired", ente.TempObjectDelete)
				require.Zero(t, c.removeUnreportedObjects())
			}
		})
	}
}

func TestWasabiTempCleanupLeavesUnexpiredUploads(t *testing.T) {
	c, _, db := setupWasabiTempCleanupTest(t, func(w http.ResponseWriter, r *http.Request) {
		t.Errorf("unexpired upload must not be modified: %s %s", r.Method, r.URL)
		w.WriteHeader(http.StatusBadRequest)
	})
	require.NoError(t, c.AddTempObject(ente.TempObject{ObjectKey: "1/recent", BucketId: cleanupWasabiDC}))
	require.Zero(t, c.removeUnreportedObjects())
	assertTempCleanupState(t, db, "1/recent", ente.TempObjectUploading)
	bucket, err := c.Repo.GetFileUploadBucket(t.Context(), "1/recent", 1, ente.Photos)
	require.NoError(t, err)
	require.Equal(t, cleanupWasabiDC, bucket)
}

func TestWasabiTempCleanupUnknownState(t *testing.T) {
	c, _, db := setupWasabiTempCleanupTest(t, func(w http.ResponseWriter, r *http.Request) {
		t.Errorf("unknown cleanup state must not modify object: %s %s", r.Method, r.URL)
		w.WriteHeader(http.StatusBadRequest)
	})
	_, err := db.Exec(`INSERT INTO temp_objects(object_key, bucket_id, expiration_time, cleanup_state)
		VALUES ('1/unknown', $1, 0, 'unknown')`, cleanupWasabiDC)
	require.NoError(t, err)
	require.Zero(t, c.removeUnreportedObjects())
	assertTempCleanupState(t, db, "1/unknown", "unknown")
	assertCleanupRowCount(t, db, `SELECT count(*) FROM temp_objects WHERE expiration_time > now_utc_micro_seconds()`, 1)
	_, err = c.Repo.GetFileUploadBucket(t.Context(), "1/unknown", 1, ente.Photos)
	require.ErrorIs(t, err, sql.ErrNoRows)
}

func TestWasabiTempCleanupWinsRegistrationRace(t *testing.T) {
	c, fileRepo, db := setupWasabiTempCleanupTest(t, func(w http.ResponseWriter, r *http.Request) {
		t.Errorf("hold release must wait for handoff commit: %s %s", r.Method, r.URL)
		w.WriteHeader(http.StatusBadRequest)
	})
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "wasabi-cleanup@ente.com", CreationTime: 1})
	collectionID := insertObjectCleanupTestCollection(t, db, ownerID)
	_, err := db.Exec(`INSERT INTO temp_objects(object_key, expiration_time, bucket_id)
		VALUES ('1/file', 0, $1), ('1/thumbnail', 0, $1)`, cleanupWasabiDC)
	require.NoError(t, err)
	tx, objects, err := c.Repo.GetAndLockExpiredObjects()
	require.NoError(t, err)
	defer tx.Rollback()
	for _, object := range objects {
		require.NoError(t, c.removeUnreportedObject(tx, object))
	}
	require.Zero(t, c.removeUnreportedObjects())
	registrationDone := make(chan error, 1)
	go func() {
		_, _, err := fileRepo.Create(objectCleanupTestFile(ownerID, collectionID, "1/file", "1/thumbnail"),
			100, 10, 110, ownerID, ente.Photos, repo.FileObjectBuckets{File: cleanupWasabiDC, Thumbnail: cleanupWasabiDC})
		registrationDone <- err
	}()
	waitForTempObjectDeleteLock(t, db)
	require.NoError(t, tx.Commit())
	select {
	case err := <-registrationDone:
		require.ErrorContains(t, err, "staged upload not found")
	case <-time.After(2 * time.Second):
		t.Fatal("registration did not finish")
	}
	assertCleanupRowCount(t, db, `SELECT count(*) FROM files`, 0)
	assertCleanupRowCount(t, db, `SELECT count(*) FROM object_keys`, 0)
	assertCleanupRowCount(t, db, `SELECT count(*) FROM temp_objects WHERE cleanup_state = 'release_hold'`, 2)
}

func TestWasabiTempCleanupPreservesRegisteredObjects(t *testing.T) {
	c, fileRepo, db := setupWasabiTempCleanupTest(t, func(w http.ResponseWriter, r *http.Request) {
		t.Errorf("registered object must not be modified: %s %s", r.Method, r.URL)
		w.WriteHeader(http.StatusBadRequest)
	})
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "registered-cleanup@ente.com", CreationTime: 1})
	testutil.InsertUsage(t, db, ownerID, 0)
	collectionID := insertObjectCleanupTestCollection(t, db, ownerID)
	_, err := db.Exec(`INSERT INTO temp_objects(object_key, expiration_time, bucket_id)
		VALUES ('1/file', 0, $1), ('1/thumbnail', 0, $1)`, cleanupWasabiDC)
	require.NoError(t, err)
	_, _, err = fileRepo.Create(objectCleanupTestFile(ownerID, collectionID, "1/file", "1/thumbnail"),
		100, 10, 110, ownerID, ente.Photos, repo.FileObjectBuckets{File: cleanupWasabiDC, Thumbnail: cleanupWasabiDC})
	require.NoError(t, err)
	for _, state := range []ente.TempObjectCleanupState{ente.TempObjectUploading, ente.TempObjectReleaseHold, ente.TempObjectDelete} {
		_, err = db.Exec(`INSERT INTO temp_objects(object_key, bucket_id, expiration_time, cleanup_state)
			VALUES ('1/file', $1, 0, NULLIF($2, '')) ON CONFLICT (object_key)
			DO UPDATE SET expiration_time = 0, cleanup_state = NULLIF($2, '')`, cleanupWasabiDC, state)
		require.NoError(t, err)
		require.Zero(t, c.removeUnreportedObjects())
		assertTempCleanupState(t, db, "1/file", state)
		assertCleanupRowCount(t, db, `SELECT count(*) FROM temp_objects WHERE expiration_time > now_utc_micro_seconds()`, 1)
	}
	assertCleanupRowCount(t, db, `SELECT count(*) FROM object_keys`, 2)
}

func setupWasabiTempCleanupTest(t *testing.T, handler http.HandlerFunc) (*ObjectCleanupController, *repo.FileRepository, *sql.DB) {
	t.Helper()
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	c, fileRepo, db := setupObjectCleanupRaceTest(t, server.URL)
	viper.Set("s3.hot_storage.primary", cleanupWasabiDC)
	viper.Set("s3.hot_storage.secondary", "b2-eu-cen")
	viper.Set("s3."+cleanupWasabiDC+".key", "test-key")
	viper.Set("s3."+cleanupWasabiDC+".secret", "test-secret")
	viper.Set("s3."+cleanupWasabiDC+".endpoint", server.URL)
	viper.Set("s3."+cleanupWasabiDC+".region", "us-east-1")
	viper.Set("s3."+cleanupWasabiDC+".bucket", "wasabi-bucket")
	viper.Set("s3."+cleanupWasabiDC+".disable_ssl", true)
	viper.Set("s3."+cleanupWasabiDC+".compliance", true)
	viper.Set("s3.b6.bucket", "")
	c.S3Config = s3config.NewS3Config()
	fileRepo.S3Config = c.S3Config
	return c, fileRepo, db
}

func assertCleanupRowCount(t *testing.T, db *sql.DB, query string, want int) {
	t.Helper()
	var count int
	require.NoError(t, db.QueryRow(query).Scan(&count))
	require.Equal(t, want, count, query)
}

func assertTempCleanupState(t *testing.T, db *sql.DB, key string, want ente.TempObjectCleanupState) {
	t.Helper()
	var state ente.TempObjectCleanupState
	require.NoError(t, db.QueryRow(`SELECT COALESCE(cleanup_state, '') FROM temp_objects WHERE object_key = $1`, key).Scan(&state))
	require.Equal(t, want, state)
}
