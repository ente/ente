package controller

import (
	"bytes"
	"context"
	"crypto/md5"
	"database/sql"
	"encoding/base64"
	"io"
	"net/http"
	"net/http/httptest"
	"path"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/public"
	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/gin-gonic/gin"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

const (
	fileBucketB2     = "b2-eu-cen"
	fileBucketWasabi = "wasabi-eu-central-2-v3"
)

func TestFileRegistrationBucketSwitch(t *testing.T) {
	for _, tc := range []struct {
		name      string
		file      string
		thumbnail string
		hot       string
	}{
		{name: "B2 to Wasabi", file: fileBucketB2, thumbnail: fileBucketB2, hot: fileBucketWasabi},
		{name: "Wasabi to B2", file: fileBucketWasabi, thumbnail: fileBucketWasabi, hot: fileBucketB2},
		{name: "mixed buckets", file: fileBucketB2, thumbnail: fileBucketWasabi, hot: fileBucketWasabi},
	} {
		t.Run(tc.name, func(t *testing.T) {
			test := newFileBucketTest(t)
			file := test.newFile(t, tc.file, tc.thumbnail)
			test.switchBucket(tc.hot)
			created, err := test.controller.Create(fileBucketContext(http.MethodPost), file.OwnerID, file, "test", ente.Photos)
			require.NoError(t, err)
			test.assertObject(t, created.ID, ente.FILE, file.File.ObjectKey, 100, []string{tc.file})
			test.assertObject(t, created.ID, ente.THUMBNAIL, file.Thumbnail.ObjectKey, 10, []string{tc.thumbnail})
			test.assertUsageAndStaging(t, 111, 0)
			beforeRetry := test.replicationState(t)

			retried, err := test.controller.Create(fileBucketContext(http.MethodPost), file.OwnerID, file, "test", ente.Photos)
			require.NoError(t, err)
			require.Equal(t, created.ID, retried.ID)
			require.Equal(t, beforeRetry, test.replicationState(t))
			test.assertUsageAndStaging(t, 111, 0)
		})
	}
}

func TestFileUpdateBucketSwitch(t *testing.T) {
	for _, tc := range []struct {
		name          string
		replaceFile   bool
		replaceThumb  bool
		thumbnailOnly bool
	}{
		{name: "both objects", replaceFile: true, replaceThumb: true},
		{name: "file only", replaceFile: true},
		{name: "thumbnail only", replaceThumb: true},
		{name: "thumbnail endpoint", replaceThumb: true, thumbnailOnly: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			test := newFileBucketTest(t)
			file := test.newFile(t, fileBucketB2, fileBucketB2)
			file, err := test.controller.Create(fileBucketContext(http.MethodPost), file.OwnerID, file, "test", ente.Photos)
			require.NoError(t, err)
			_, err = test.db.Exec(`UPDATE object_keys SET datacenters = ARRAY['b2-eu-cen', 'wasabi-eu-central-2-v3']::s3region[];
				UPDATE object_copies SET wasabi = 1`)
			require.NoError(t, err)
			fileLocations := []string{fileBucketB2, fileBucketWasabi}
			thumbnailLocations := fileLocations
			if tc.replaceFile {
				file.File.ObjectKey = test.upload(t, fileBucketWasabi, 100)
				fileLocations = []string{fileBucketWasabi}
			}
			if tc.replaceThumb {
				file.Thumbnail.ObjectKey = test.upload(t, fileBucketWasabi, 10)
				thumbnailLocations = []string{fileBucketWasabi}
			}
			test.switchBucket(fileBucketB2)
			update := func() error {
				if tc.thumbnailOnly {
					return test.controller.UpdateThumbnail(fileBucketContext(http.MethodPut), file.ID, file.Thumbnail, ente.Photos)
				}
				_, err := test.controller.Update(t.Context(), file.OwnerID, file, ente.Photos)
				return err
			}
			require.NoError(t, update())
			test.assertObject(t, file.ID, ente.FILE, file.File.ObjectKey, 100, fileLocations)
			test.assertObject(t, file.ID, ente.THUMBNAIL, file.Thumbnail.ObjectKey, 10, thumbnailLocations)
			test.assertUsageAndStaging(t, 111, 0)
			beforeRetry := test.replicationState(t)

			test.switchBucket(fileBucketWasabi)
			require.NoError(t, update())
			require.Equal(t, beforeRetry, test.replicationState(t))
			test.assertObject(t, file.ID, ente.FILE, file.File.ObjectKey, 100, fileLocations)
			test.assertObject(t, file.ID, ente.THUMBNAIL, file.Thumbnail.ObjectKey, 10, thumbnailLocations)
			test.assertUsageAndStaging(t, 111, 0)
		})
	}
}

func TestFileRegistrationRejectsInvalidStagedUpload(t *testing.T) {
	for _, tc := range []struct {
		name   string
		change string
	}{
		{name: "unknown bucket", change: "bucket_id = NULL"},
		{name: "wrong app", change: "app = 'locker'"},
		{name: "wrong purpose", change: "purpose = 'attachment'"},
		{name: "wrong owner", change: "user_id = 2"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			test := newFileBucketTest(t)
			file := test.newFile(t, fileBucketB2, fileBucketB2)
			_, err := test.db.Exec(`UPDATE temp_objects SET `+tc.change+` WHERE object_key = $1`, file.Thumbnail.ObjectKey)
			require.NoError(t, err)
			test.switchBucket(fileBucketWasabi)
			_, err = test.controller.Create(fileBucketContext(http.MethodPost), file.OwnerID, file, "test", ente.Photos)
			var apiErr *ente.ApiError
			require.ErrorAs(t, err, &apiErr)
			require.Equal(t, ente.BadRequest, apiErr.Code)
			require.Equal(t, http.StatusBadRequest, apiErr.HttpStatusCode)
			var count int
			require.NoError(t, test.db.QueryRow(`SELECT COUNT(*) FROM files`).Scan(&count))
			require.Zero(t, count)
			test.assertUsageAndStaging(t, 1, 2)
		})
	}
}

func TestFileRegistrationConflictResetsMixedBucketReplicas(t *testing.T) {
	for _, tc := range []struct {
		name              string
		commitAfterLookup bool
	}{
		{name: "committed before lookup"},
		{name: "committed in separate files after lookup", commitAfterLookup: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			test := newFileBucketTest(t)
			file := test.newFile(t, fileBucketB2, fileBucketWasabi)
			var fileObject, thumbnailObject uploadedObject
			if tc.commitAfterLookup {
				var err error
				fileObject, err = test.controller.getUploadedObject(t.Context(), file.File.ObjectKey, file.OwnerID, ente.Photos)
				require.NoError(t, err)
				thumbnailObject, err = test.controller.getUploadedObject(t.Context(), file.Thumbnail.ObjectKey, file.OwnerID, ente.Photos)
				require.NoError(t, err)
			}
			first := file
			storageUsed := int64(111)
			if tc.commitAfterLookup {
				second := test.newFile(t, fileBucketB2, fileBucketWasabi)
				first.Thumbnail, second.Thumbnail = second.Thumbnail, file.Thumbnail
				_, err := test.controller.Create(fileBucketContext(http.MethodPost), second.OwnerID, second, "test", ente.Photos)
				require.NoError(t, err)
				storageUsed += 110
			}
			existing, err := test.controller.Create(fileBucketContext(http.MethodPost), first.OwnerID, first, "test", ente.Photos)
			require.NoError(t, err)
			_, err = test.db.Exec(`UPDATE object_copies SET b2 = 1, wasabi = 1, scw = CASE WHEN want_scw THEN 1 END`)
			require.NoError(t, err)
			file.File.DecryptionHeader = "conflicting-header"
			test.switchBucket(fileBucketWasabi)
			if tc.commitAfterLookup {
				file.File.Size, file.Thumbnail.Size = fileObject.size, thumbnailObject.size
				ctx := fileBucketContext(http.MethodPost)
				requestCtx, cancel := context.WithCancel(ctx.Request.Context())
				ctx.Request = ctx.Request.WithContext(requestCtx)
				cancel()
				_, err = test.controller.onDuplicateObjectDetected(ctx, file, existing, ente.Photos)
			} else {
				_, err = test.controller.Create(fileBucketContext(http.MethodPost), file.OwnerID, file, "test", ente.Photos)
			}
			require.ErrorIs(t, err, ente.ErrFileUploadConflict)
			require.Eventually(t, func() bool {
				var reset bool
				err := test.db.QueryRow(`SELECT bool_and(CASE WHEN object_key = $1
					THEN b2 = 1 AND wasabi IS NULL AND scw IS NULL
					ELSE b2 IS NULL AND wasabi = 1 END) FROM object_copies
					WHERE object_key IN ($1, $2)`, file.File.ObjectKey, file.Thumbnail.ObjectKey).Scan(&reset)
				return err == nil && reset
			}, 2*time.Second, 10*time.Millisecond)
			test.storageMutex.Lock()
			versionLists := make(map[string]int, len(test.versionLists))
			for key, count := range test.versionLists {
				versionLists[key] = count
			}
			test.storageMutex.Unlock()
			require.Equal(t, map[string]int{
				"/" + fileBucketB2 + "/" + file.File.ObjectKey:          1,
				"/" + fileBucketWasabi + "/" + file.Thumbnail.ObjectKey: 1,
			}, versionLists)
			test.assertUsageAndStaging(t, storageUsed, 0)
		})
	}
}

func TestFileRegistrationConflictPreservesStagedPartner(t *testing.T) {
	test := newFileBucketTest(t)
	file := test.newFile(t, fileBucketWasabi, fileBucketWasabi)
	_, err := test.controller.Create(fileBucketContext(http.MethodPost), file.OwnerID, file, "test", ente.Photos)
	require.NoError(t, err)
	_, err = test.db.Exec(`UPDATE object_copies SET b2 = 1, wasabi = 1, scw = CASE WHEN want_scw THEN 1 END`)
	require.NoError(t, err)
	originalThumbnail := file.Thumbnail.ObjectKey
	var thumbnailReplicas string
	require.NoError(t, test.db.QueryRow(`SELECT to_jsonb(object_copies)::text FROM object_copies WHERE object_key = $1`, originalThumbnail).Scan(&thumbnailReplicas))
	file.Thumbnail.ObjectKey = test.upload(t, fileBucketB2, 10)
	test.storageMutex.Lock()
	test.versionResponses["/"+fileBucketB2+"/"+file.Thumbnail.ObjectKey] = `<ListVersionsResult><Version><VersionId>new-version</VersionId></Version><Version><VersionId>old-version</VersionId></Version></ListVersionsResult>`
	test.storageMutex.Unlock()

	test.controller.onExistingObjectsReplaced(fileBucketContext(http.MethodPost), file)
	var reset bool
	require.NoError(t, test.db.QueryRow(`SELECT b2 IS NULL AND wasabi = 1 AND scw IS NULL FROM object_copies WHERE object_key = $1`, file.File.ObjectKey).Scan(&reset))
	require.True(t, reset)
	test.storageMutex.Lock()
	versionLists := make(map[string]int, len(test.versionLists))
	for key, count := range test.versionLists {
		versionLists[key] = count
	}
	test.storageMutex.Unlock()
	require.Equal(t, map[string]int{"/" + fileBucketWasabi + "/" + file.File.ObjectKey: 1}, versionLists)
	var unchangedThumbnailReplicas string
	require.NoError(t, test.db.QueryRow(`SELECT to_jsonb(object_copies)::text FROM object_copies WHERE object_key = $1`, originalThumbnail).Scan(&unchangedThumbnailReplicas))
	require.Equal(t, thumbnailReplicas, unchangedThumbnailReplicas)
	var stagedBucket string
	require.NoError(t, test.db.QueryRow(`SELECT bucket_id FROM temp_objects WHERE object_key = $1`, file.Thumbnail.ObjectKey).Scan(&stagedBucket))
	require.Equal(t, fileBucketB2, stagedBucket)
	var copies int
	require.NoError(t, test.db.QueryRow(`SELECT COUNT(*) FROM object_copies WHERE object_key = $1`, file.Thumbnail.ObjectKey).Scan(&copies))
	require.Zero(t, copies)
	test.assertUsageAndStaging(t, 111, 1)
}

func TestFileUpdateRejectsUnchangedObjectChanges(t *testing.T) {
	for _, change := range []string{"size", "decryption header"} {
		for _, tc := range []struct {
			name           string
			thumbnail      bool
			replacePartner bool
			thumbnailOnly  bool
		}{
			{name: "unchanged file"},
			{name: "unchanged file during thumbnail replacement", replacePartner: true},
			{name: "unchanged thumbnail during file replacement", thumbnail: true, replacePartner: true},
			{name: "thumbnail endpoint", thumbnail: true, thumbnailOnly: true},
		} {
			t.Run(change+"/"+tc.name, func(t *testing.T) {
				test := newFileBucketTest(t)
				file := test.newFile(t, fileBucketB2, fileBucketB2)
				file, err := test.controller.Create(fileBucketContext(http.MethodPost), file.OwnerID, file, "test", ente.Photos)
				require.NoError(t, err)
				existing := file
				beforeUpdate := test.replicationState(t)
				staged := 0
				if tc.replacePartner {
					if tc.thumbnail {
						file.File.ObjectKey = test.upload(t, fileBucketWasabi, 100)
					} else {
						file.Thumbnail.ObjectKey = test.upload(t, fileBucketWasabi, 10)
					}
					staged = 1
				}
				attributes := &file.File
				if tc.thumbnail {
					attributes = &file.Thumbnail
				}
				if change == "decryption header" {
					attributes.DecryptionHeader = "conflicting-header"
				} else {
					test.storageMutex.Lock()
					test.storageObjects["/"+fileBucketB2+"/"+attributes.ObjectKey] = attributes.Size - 1
					test.storageMutex.Unlock()
					file.File.Size, file.Thumbnail.Size = 0, 0
				}
				test.switchBucket(fileBucketWasabi)
				if tc.thumbnailOnly {
					err = test.controller.UpdateThumbnail(fileBucketContext(http.MethodPut), file.ID, file.Thumbnail, ente.Photos)
				} else {
					_, err = test.controller.Update(t.Context(), file.OwnerID, file, ente.Photos)
				}
				require.ErrorIs(t, err, ente.ErrFileUploadConflict)
				require.Equal(t, beforeUpdate, test.replicationState(t))
				test.assertObject(t, file.ID, ente.FILE, existing.File.ObjectKey, 100, []string{fileBucketB2})
				test.assertObject(t, file.ID, ente.THUMBNAIL, existing.Thumbnail.ObjectKey, 10, []string{fileBucketB2})
				stored, err := test.controller.FileRepo.GetFileAttributes(file.ID)
				require.NoError(t, err)
				require.Equal(t, existing.File.DecryptionHeader, stored.File.DecryptionHeader)
				require.Equal(t, existing.Thumbnail.DecryptionHeader, stored.Thumbnail.DecryptionHeader)
				test.assertUsageAndStaging(t, 111, staged)
			})
		}
	}
}

type fileBucketTest struct {
	controller       *FileController
	db               *sql.DB
	collectionID     int64
	storageObjects   map[string]int64
	storageMutex     *sync.Mutex
	versionLists     map[string]int
	versionResponses map[string]string
}

func newFileBucketTest(t *testing.T) *fileBucketTest {
	t.Helper()
	objects := make(map[string]int64)
	versionLists := make(map[string]int)
	versionResponses := make(map[string]string)
	var mutex sync.Mutex
	storage := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodPut:
			size, err := io.Copy(io.Discard, r.Body)
			if err != nil {
				t.Errorf("read upload: %v", err)
				w.WriteHeader(http.StatusBadRequest)
				return
			}
			mutex.Lock()
			objects[r.URL.Path] = size
			mutex.Unlock()
		case http.MethodHead:
			mutex.Lock()
			size, exists := objects[r.URL.Path]
			mutex.Unlock()
			if !exists {
				t.Errorf("HEAD requested an object outside its upload bucket: %s", r.URL.Path)
				w.WriteHeader(http.StatusNotFound)
				return
			}
			w.Header().Set("Content-Length", strconv.FormatInt(size, 10))
		case http.MethodGet:
			objectPath := path.Join(r.URL.Path, r.URL.Query().Get("prefix"))
			mutex.Lock()
			_, exists := objects[objectPath]
			versionLists[objectPath]++
			response := versionResponses[objectPath]
			mutex.Unlock()
			if !r.URL.Query().Has("versions") || !exists {
				t.Errorf("unexpected version lookup: %s", r.URL)
				w.WriteHeader(http.StatusBadRequest)
				return
			}
			if response == "" {
				response = `<ListVersionsResult/>`
			}
			_, _ = w.Write([]byte(response))
		default:
			t.Errorf("unexpected storage request: %s %s", r.Method, r.URL)
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	}))
	t.Cleanup(storage.Close)
	cleanup, repository, db := setupObjectCleanupRaceTest(t, storage.URL)
	for _, bucket := range []string{fileBucketB2, fileBucketWasabi} {
		for key, value := range map[string]any{
			"key": "test-key", "secret": "test-secret", "endpoint": storage.URL,
			"region": "us-east-1", "bucket": bucket, "disable_ssl": true,
		} {
			viper.Set("s3."+bucket+"."+key, value)
		}
	}
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "bucket-switch@ente.com", CreationTime: 1})
	testutil.InsertUsage(t, db, ownerID, 1)
	testutil.InsertSubscription(t, db, testutil.SubscriptionFixture{UserID: ownerID, Storage: 1 << 30, ExpiryTime: time.Now().Add(time.Hour).UnixMicro()})
	users := &repo.UserRepository{DB: db}
	test := &fileBucketTest{
		db: db, collectionID: insertObjectCleanupTestCollection(t, db, ownerID),
		storageObjects: objects, storageMutex: &mutex,
		versionLists: versionLists, versionResponses: versionResponses,
		controller: &FileController{
			FileRepo: repository, ObjectRepo: repository.ObjectRepo,
			ObjectCleanupRepo: cleanup.Repo, ObjectCleanupCtrl: cleanup,
			CollectionRepo: &repo.CollectionRepository{DB: db, CollectionLinkRepo: &public.CollectionLinkRepo{DB: db}},
			UsageCtrl: &UsageController{
				UserRepo: users, UsageRepo: &repo.UsageRepository{DB: db}, UploadResultCache: make(map[int64]bool),
				BillingCtrl: &BillingController{UserRepo: users, BillingRepo: &repo.BillingRepository{DB: db}},
			},
		},
	}
	test.switchBucket(fileBucketB2)
	return test
}

func (test *fileBucketTest) switchBucket(bucket string) {
	secondary := fileBucketB2
	if bucket == fileBucketB2 {
		secondary = fileBucketWasabi
	}
	viper.Set("s3.hot_storage.primary", bucket)
	viper.Set("s3.hot_storage.secondary", secondary)
	config := s3config.NewS3Config()
	test.controller.S3Config = config
	test.controller.FileRepo.S3Config = config
	test.controller.ObjectCleanupCtrl.S3Config = config
}

func (test *fileBucketTest) upload(t *testing.T, bucket string, size int) string {
	t.Helper()
	test.switchBucket(bucket)
	body := bytes.Repeat([]byte("x"), size)
	checksum := md5.Sum(body)
	encodedChecksum := base64.StdEncoding.EncodeToString(checksum[:])
	upload, err := test.controller.GetUploadURLWithMetadata(t.Context(), 1, ente.UploadURLRequest{
		ContentLength: int64(size), ContentMD5: encodedChecksum,
	}, ente.Photos, "test")
	require.NoError(t, err)
	request, err := http.NewRequestWithContext(t.Context(), http.MethodPut, upload.URL, bytes.NewReader(body))
	require.NoError(t, err)
	request.Header.Set("Content-MD5", encodedChecksum)
	response, err := http.DefaultClient.Do(request)
	require.NoError(t, err)
	require.NoError(t, response.Body.Close())
	require.Equal(t, http.StatusOK, response.StatusCode)
	return upload.ObjectKey
}

func (test *fileBucketTest) newFile(t *testing.T, fileBucket, thumbnailBucket string) ente.File {
	t.Helper()
	return objectCleanupTestFile(1, test.collectionID, test.upload(t, fileBucket, 100), test.upload(t, thumbnailBucket, 10))
}

func (test *fileBucketTest) assertObject(t *testing.T, fileID int64, objectType ente.ObjectType, key string, size int64, locations []string) {
	t.Helper()
	object, actualLocations, err := test.controller.ObjectRepo.GetObjectWithDCs(fileID, objectType)
	require.NoError(t, err)
	require.Equal(t, key, object.ObjectKey)
	require.Equal(t, size, object.FileSize)
	require.Equal(t, locations, actualLocations)
	var b2, wasabi sql.NullInt64
	var wantB2, wantWasabi, wantScw bool
	require.NoError(t, test.db.QueryRow(`SELECT b2, wasabi, want_b2, want_wasabi, want_scw FROM object_copies WHERE object_key = $1`, key).
		Scan(&b2, &wasabi, &wantB2, &wantWasabi, &wantScw))
	require.Equal(t, locations[0] == fileBucketB2 || len(locations) > 1, b2.Valid)
	require.Equal(t, locations[0] == fileBucketWasabi || len(locations) > 1, wasabi.Valid)
	require.True(t, wantB2)
	require.True(t, wantWasabi)
	require.Equal(t, objectType == ente.FILE, wantScw)
}

func (test *fileBucketTest) assertUsageAndStaging(t *testing.T, storage int64, staged int) {
	t.Helper()
	var actualStorage int64
	var actualStaged int
	require.NoError(t, test.db.QueryRow(`SELECT storage_consumed, (SELECT COUNT(*) FROM temp_objects) FROM usage WHERE user_id = 1`).Scan(&actualStorage, &actualStaged))
	require.Equal(t, storage, actualStorage)
	require.Equal(t, staged, actualStaged)
}

func (test *fileBucketTest) replicationState(t *testing.T) string {
	t.Helper()
	var state string
	require.NoError(t, test.db.QueryRow(`SELECT jsonb_agg(to_jsonb(object_copies) ORDER BY object_key)::text FROM object_copies`).Scan(&state))
	return state
}

func fileBucketContext(method string) *gin.Context {
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	ctx.Request = httptest.NewRequest(method, "/files", nil)
	ctx.Request.Header.Set("X-Auth-User-ID", "1")
	return ctx
}
