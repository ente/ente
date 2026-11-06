package file_copy

import (
	"context"
	"database/sql"
	"encoding/base64"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/controller/access"
	"github.com/ente/museum/pkg/controller/collections"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/public"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/gin-gonic/gin"
	"github.com/lib/pq"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	copyB2     = "b2-eu-cen"
	copyWasabi = "wasabi-eu-central-2-v3"
)

func TestCopyBucket(t *testing.T) {
	for _, primary := range []string{copyB2, copyWasabi} {
		fc := &FileCopyController{S3Config: copyTestConfig(t, primary, "http://127.0.0.1")}
		for _, tc := range []struct {
			name string
			dcs  []string
			want string
		}{
			{"both", []string{copyWasabi, copyB2}, primary},
			{"b2", []string{copyB2}, copyB2},
			{"wasabi", []string{copyWasabi}, copyWasabi},
			{"cold", []string{"scw-eu-fr-v3"}, ""},
			{"obsolete", []string{"wasabi-eu-central-2"}, ""},
			{"empty", nil, ""},
		} {
			t.Run(primary+"/"+tc.name, func(t *testing.T) {
				bucket, err := fc.copyBucket(tc.dcs)
				if tc.want == "" {
					require.ErrorContains(t, err, "no recorded hot storage copy")
				} else {
					require.NoError(t, err)
				}
				require.Equal(t, tc.want, bucket)
			})
		}
	}
}

func TestCopyFilesBuckets(t *testing.T) {
	for _, tc := range []struct {
		name      string
		primary   string
		fileDCs   []string
		thumbDCs  []string
		fileWant  string
		thumbWant string
	}{
		{"b2 primary", copyB2, []string{copyB2, copyWasabi}, []string{copyB2, copyWasabi}, copyB2, copyB2},
		{"wasabi primary", copyWasabi, []string{copyB2, copyWasabi}, []string{copyB2, copyWasabi}, copyWasabi, copyWasabi},
		{"b2 only after switch", copyWasabi, []string{copyB2}, []string{copyB2}, copyB2, copyB2},
		{"wasabi only after switch back", copyB2, []string{copyWasabi}, []string{copyWasabi}, copyWasabi, copyWasabi},
		{"mixed", copyWasabi, []string{copyB2}, []string{copyWasabi}, copyB2, copyWasabi},
	} {
		t.Run(tc.name, func(t *testing.T) {
			fc, request, ctx, db, _, _ := setupCopyTest(t, tc.primary, tc.fileDCs, tc.thumbDCs, false)
			result, err := fc.CopyFiles(ctx, request)
			require.NoError(t, err)
			fileID := result.OldToNewFileIDMap[request.CollectionFileItems[0].ID]
			require.NotZero(t, fileID)
			for _, object := range []struct {
				typeID ente.ObjectType
				bucket string
				size   int64
			}{{ente.FILE, tc.fileWant, 100}, {ente.THUMBNAIL, tc.thumbWant, 10}} {
				copied, dcs, err := fc.ObjectRepo.GetObjectWithDCs(fileID, object.typeID)
				require.NoError(t, err)
				require.True(t, strings.HasPrefix(copied.ObjectKey, "1/"))
				require.Equal(t, object.size, copied.FileSize)
				require.Equal(t, []string{object.bucket}, dcs)
				var b2, wasabi sql.NullInt64
				require.NoError(t, db.QueryRow(`SELECT b2, wasabi FROM object_copies WHERE object_key = $1`, copied.ObjectKey).Scan(&b2, &wasabi))
				require.Equal(t, object.bucket == copyB2, b2.Valid)
				require.Equal(t, object.bucket == copyWasabi, wasabi.Valid)
			}
			var staged int
			var usage int64
			require.NoError(t, db.QueryRow(`SELECT (SELECT COUNT(*) FROM temp_objects), storage_consumed FROM usage WHERE user_id = 1`).Scan(&staged, &usage))
			require.Zero(t, staged)
			require.EqualValues(t, 111, usage)
		})
	}
}

func TestCopyFilesFailure(t *testing.T) {
	for _, mode := range []string{"unavailable source", "no hot replica", "permission denied"} {
		t.Run(mode, func(t *testing.T) {
			fileDCs := []string{copyB2}
			if mode == "no hot replica" {
				fileDCs = []string{"scw-eu-fr-v3"}
			}
			fc, request, ctx, db, _, _ := setupCopyTest(t, copyWasabi, fileDCs, []string{copyWasabi}, mode == "unavailable source")
			if mode == "permission denied" {
				_, err := db.Exec(`DELETE FROM collection_shares`)
				require.NoError(t, err)
			}
			result, err := fc.CopyFiles(ctx, request)
			require.Error(t, err)
			if mode == "no hot replica" {
				require.ErrorContains(t, err, "no recorded hot storage copy")
			}
			require.Nil(t, result)
			var files, staged int
			var usage int64
			require.NoError(t, db.QueryRow(`SELECT (SELECT COUNT(*) FROM files WHERE owner_id = 1),
				(SELECT COUNT(*) FROM temp_objects), storage_consumed FROM usage WHERE user_id = 1`).Scan(&files, &staged, &usage))
			require.Zero(t, files)
			require.EqualValues(t, 1, usage)
			if mode == "unavailable source" {
				require.Equal(t, 2, staged)
			} else {
				require.Zero(t, staged)
			}
		})
	}
}

func TestCopyS3ObjectStaging(t *testing.T) {
	for _, mode := range []string{"success", "staging failure", "cancelled"} {
		t.Run(mode, func(t *testing.T) {
			fc, _, _, db, objects, mutex := setupCopyTest(t, copyWasabi, []string{copyB2}, []string{copyWasabi}, false)
			req := &copyS3ObjectReq{
				SourceS3Object: ente.S3ObjectKey{ObjectKey: "2/file", Type: ente.FILE},
				Destination:    ente.TempObject{ObjectKey: "1/new-file", BucketId: copyB2, UserID: 1, App: ente.Photos, Purpose: "file_upload"},
			}
			if mode == "staging failure" {
				require.NoError(t, fc.FileController.ObjectCleanupCtrl.AddTempObject(req.Destination))
			}
			ctx, cancel := context.WithCancel(t.Context())
			defer cancel()
			if mode == "cancelled" {
				cancel()
			}
			err := fc.copyS3Object(ctx, req)
			if mode == "success" {
				require.NoError(t, err)
			} else {
				require.Error(t, err)
			}
			mutex.Lock()
			_, copied := objects["/"+copyB2+"/1/new-file"]
			mutex.Unlock()
			require.Equal(t, mode == "success", copied)
			var bucket string
			require.NoError(t, db.QueryRow(`SELECT bucket_id FROM temp_objects WHERE object_key = '1/new-file'`).Scan(&bucket))
			require.Equal(t, copyB2, bucket)
		})
	}
}

func copyTestConfig(t *testing.T, primary, endpoint string) *s3config.S3Config {
	t.Helper()
	viper.Reset()
	t.Cleanup(viper.Reset)
	secondary := copyB2
	if primary == copyB2 {
		secondary = copyWasabi
	}
	viper.Set("s3.hot_storage.primary", primary)
	viper.Set("s3.hot_storage.secondary", secondary)
	viper.Set("s3.use_path_style_urls", true)
	for _, dc := range []string{copyB2, copyWasabi} {
		for key, value := range map[string]any{"bucket": dc, "endpoint": endpoint, "region": "us-east-1", "key": "test-key", "secret": "test-secret", "disable_ssl": true} {
			viper.Set("s3."+dc+"."+key, value)
		}
	}
	return s3config.NewS3Config()
}

func setupCopyTest(t *testing.T, primary string, fileDCs, thumbDCs []string, failFile bool) (*FileCopyController, ente.CopyFileSyncRequest, *gin.Context, *sql.DB, map[string]int64, *sync.Mutex) {
	t.Helper()
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	for _, id := range []int64{1, 2} {
		testutil.InsertUser(t, db, testutil.UserFixture{UserID: id, Email: fmt.Sprintf("copy%d@ente.test", id), CreationTime: 1})
	}
	testutil.InsertUsage(t, db, 1, 1)
	testutil.InsertSubscription(t, db, testutil.SubscriptionFixture{UserID: 1, Storage: 1 << 30, ExpiryTime: time.Now().Add(time.Hour).UnixMicro()})
	collectionIDs := make([]int64, 2)
	for i := range collectionIDs {
		require.NoError(t, db.QueryRow(`INSERT INTO collections(owner_id, encrypted_key, key_decryption_nonce, name, type, attributes, updation_time, app)
			VALUES ($1, 'key', 'nonce', 'Copy', 'album', '{}', 1, 'photos') RETURNING collection_id`, i+1).Scan(&collectionIDs[i]))
	}
	_, err := db.Exec(`INSERT INTO collection_shares(collection_id, from_user_id, to_user_id, encrypted_key, updation_time, role_type, shared_at)
		VALUES ($1, 2, 1, 'key', 1, 'VIEWER', 1)`, collectionIDs[1])
	require.NoError(t, err)
	var fileID int64
	require.NoError(t, db.QueryRow(`INSERT INTO files(owner_id, file_decryption_header, thumbnail_decryption_header,
		metadata_decryption_header, encrypted_metadata, updation_time, app)
		VALUES (2, 'file-header', 'thumb-header', 'metadata-header', 'metadata', 1, 'photos') RETURNING file_id`).Scan(&fileID))
	_, err = db.Exec(`INSERT INTO collection_files(collection_id, file_id, encrypted_key, key_decryption_nonce, updation_time, c_owner_id, f_owner_id)
		VALUES ($1, $2, 'key', 'nonce', 1, 2, 2)`, collectionIDs[1], fileID)
	require.NoError(t, err)
	_, err = db.Exec(`INSERT INTO object_keys(file_id, o_type, object_key, size, datacenters)
		VALUES ($1, 'file', '2/file', 100, $2), ($1, 'thumbnail', '2/thumbnail', 10, $3)`, fileID, pq.Array(fileDCs), pq.Array(thumbDCs))
	require.NoError(t, err)
	objects := make(map[string]int64)
	for _, dc := range fileDCs {
		objects["/"+dc+"/2/file"] = 100
	}
	for _, dc := range thumbDCs {
		objects["/"+dc+"/2/thumbnail"] = 10
	}
	mutex := &sync.Mutex{}
	storage := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mutex.Lock()
		defer mutex.Unlock()
		switch r.Method {
		case http.MethodPut:
			source, err := url.PathUnescape(r.Header.Get("X-Amz-Copy-Source"))
			if !assert.NoError(t, err) || !assert.NotEmpty(t, source) {
				w.WriteHeader(http.StatusBadRequest)
				return
			}
			destination := strings.SplitN(strings.TrimPrefix(r.URL.Path, "/"), "/", 2)
			assert.True(t, strings.HasPrefix(source, destination[0]+"/"), "copy crossed buckets")
			var bucket, app, purpose string
			var userID int64
			err = db.QueryRow(`SELECT bucket_id, user_id, app, purpose FROM temp_objects WHERE object_key = $1`, destination[1]).Scan(&bucket, &userID, &app, &purpose)
			assert.NoError(t, err)
			assert.Equal(t, destination[0], bucket)
			assert.EqualValues(t, 1, userID)
			assert.Equal(t, "photos", app)
			assert.Equal(t, "file_upload", purpose)
			if failFile && strings.HasSuffix(source, "/2/file") {
				w.WriteHeader(http.StatusForbidden)
				_, _ = w.Write([]byte(`<Error><Code>AccessDenied</Code></Error>`))
				return
			}
			size, exists := objects["/"+source]
			if !exists {
				w.WriteHeader(http.StatusNotFound)
				return
			}
			objects[r.URL.Path] = size
			_, _ = w.Write([]byte(`<CopyObjectResult><ETag>"copied"</ETag></CopyObjectResult>`))
		case http.MethodHead:
			size, exists := objects[r.URL.Path]
			if !exists {
				w.WriteHeader(http.StatusNotFound)
				return
			}
			w.Header().Set("Content-Length", strconv.FormatInt(size, 10))
		default:
			t.Errorf("unexpected storage request: %s", r.Method)
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	}))
	t.Cleanup(storage.Close)
	config := copyTestConfig(t, primary, storage.URL)
	objectsRepo := &repo.ObjectRepository{DB: db}
	cleanupRepo := &repo.ObjectCleanupRepository{DB: db}
	fileRepo := &repo.FileRepository{DB: db, S3Config: config, ObjectRepo: objectsRepo, ObjectCleanupRepo: cleanupRepo, ObjectCopiesRepo: &repo.ObjectCopiesRepository{DB: db}}
	collectionRepo := &repo.CollectionRepository{DB: db, CollectionLinkRepo: &public.CollectionLinkRepo{DB: db}}
	users := &repo.UserRepository{DB: db}
	fc := &FileCopyController{
		S3Config: config, ObjectRepo: objectsRepo, FileRepo: fileRepo,
		CollectionCtrl: &collections.CollectionController{AccessCtrl: access.NewAccessController(collectionRepo, nil), CollectionRepo: collectionRepo, FileRepo: fileRepo},
		FileController: &controller.FileController{
			S3Config: config, ObjectRepo: objectsRepo, FileRepo: fileRepo, ObjectCleanupRepo: cleanupRepo, CollectionRepo: collectionRepo,
			ObjectCleanupCtrl: &controller.ObjectCleanupController{Repo: cleanupRepo},
			UsageCtrl: &controller.UsageController{
				UserRepo: users, UsageRepo: &repo.UsageRepository{DB: db}, UploadResultCache: make(map[int64]bool),
				BillingCtrl: &controller.BillingController{UserRepo: users, BillingRepo: &repo.BillingRepository{DB: db}},
			},
		},
	}
	request := ente.CopyFileSyncRequest{
		SrcCollectionID: collectionIDs[1], DstCollection: collectionIDs[0],
		CollectionFileItems: []ente.CollectionFileItem{{ID: fileID, EncryptedKey: base64.StdEncoding.EncodeToString(make([]byte, 48)), KeyDecryptionNonce: base64.StdEncoding.EncodeToString(make([]byte, 24))}},
	}
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	ctx.Request = httptest.NewRequest(http.MethodPost, "/files/copy", nil)
	ctx.Request.Header.Set("X-Auth-User-ID", "1")
	ctx.Set(auth.AppContextKey, ente.Photos)
	return fc, request, ctx, db, objects, mutex
}
