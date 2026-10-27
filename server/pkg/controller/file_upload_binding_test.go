package controller

import (
	"database/sql"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/public"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestFileRegistrationUploadBinding(t *testing.T) {
	for _, tc := range []struct {
		name       string
		app        ente.App
		stagedApp  ente.App
		stagedUser int64
		purpose    string
		legacy     bool
		allowed    bool
	}{
		{name: "photos", app: ente.Photos, stagedApp: ente.Photos, stagedUser: 1, purpose: "file_upload", allowed: true},
		{name: "locker", app: ente.Locker, stagedApp: ente.Locker, stagedUser: 1, purpose: "file_upload", allowed: true},
		{name: "legacy", app: ente.Photos, legacy: true, allowed: true},
		{name: "wrong app", app: ente.Photos, stagedApp: ente.Locker, stagedUser: 1, purpose: "file_upload"},
		{name: "wrong owner", app: ente.Photos, stagedApp: ente.Photos, stagedUser: 2, purpose: "file_upload"},
		{name: "attachment", app: ente.Photos, stagedApp: ente.Photos, stagedUser: 1, purpose: "attachment"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, repository, db := setupObjectCleanupRaceTest(t, "http://127.0.0.1")
			ownerID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "upload-binding@ente.com", CreationTime: 1})
			testutil.InsertUsage(t, db, ownerID, 0)
			collectionID := insertObjectCleanupTestCollection(t, db, ownerID)
			_, err := db.Exec(`UPDATE collections SET app = $1 WHERE collection_id = $2`, tc.app, collectionID)
			require.NoError(t, err)
			file := objectCleanupTestFile(ownerID, collectionID, "1/binding-file", "1/binding-thumbnail")
			for _, key := range []string{file.File.ObjectKey, file.Thumbnail.ObjectKey} {
				_, err = db.Exec(`INSERT INTO temp_objects (object_key, expiration_time, user_id, app, purpose)
					VALUES ($1, 1, $2, $3, 'file_upload')`, key, ownerID, tc.app)
				require.NoError(t, err)
			}
			if tc.legacy {
				_, err = db.Exec(`UPDATE temp_objects SET user_id = NULL, app = NULL, purpose = NULL`)
			} else {
				_, err = db.Exec(`UPDATE temp_objects SET user_id = $1, app = $2, purpose = $3 WHERE object_key = $4`,
					tc.stagedUser, tc.stagedApp, tc.purpose, file.Thumbnail.ObjectKey)
			}
			require.NoError(t, err)

			_, _, err = repository.Create(file, 100, 10, 110, ownerID, tc.app)
			if tc.allowed {
				require.NoError(t, err)
			} else {
				var apiErr *ente.ApiError
				require.ErrorAs(t, err, &apiErr)
				require.Equal(t, "staged upload not found", apiErr.Message)
			}
			var files, staged int
			var storage int64
			require.NoError(t, db.QueryRow(`SELECT (SELECT COUNT(*) FROM files),
				(SELECT COUNT(*) FROM temp_objects), storage_consumed FROM usage WHERE user_id = $1`, ownerID).
				Scan(&files, &staged, &storage))
			if tc.allowed {
				require.Equal(t, 1, files)
				require.Zero(t, staged)
				require.EqualValues(t, 110, storage)
			} else {
				require.Zero(t, files)
				require.Equal(t, 2, staged)
				require.Zero(t, storage)
			}
		})
	}
}

func TestFileUpdateUploadBinding(t *testing.T) {
	for _, tc := range []struct {
		name       string
		app        ente.App
		requestApp ente.App
		stagedApp  ente.App
		legacy     bool
	}{
		{name: "photos", app: ente.Photos, requestApp: ente.Photos, stagedApp: ente.Photos},
		{name: "locker", app: ente.Locker, requestApp: ente.Locker, stagedApp: ente.Locker},
		{name: "wrong request app", app: ente.Photos, requestApp: ente.Locker, stagedApp: ente.Locker},
		{name: "legacy cross-app", app: ente.Locker, requestApp: ente.Photos, stagedApp: ente.Photos, legacy: true},
		{name: "wrong staged app", app: ente.Photos, requestApp: ente.Photos, stagedApp: ente.Locker},
		{name: "legacy wrong staged app", app: ente.Locker, requestApp: ente.Photos, stagedApp: ente.Locker, legacy: true},
	} {
		for _, thumbnailOnly := range []bool{false, true} {
			name := tc.name + "/file"
			if thumbnailOnly {
				name = tc.name + "/thumbnail"
			}
			t.Run(name, func(t *testing.T) {
				controller, file, db := setupFileUploadBindingTest(t, tc.app)
				if tc.legacy {
					_, err := db.Exec(`UPDATE files SET app = NULL WHERE file_id = $1`, file.ID)
					require.NoError(t, err)
				}
				file.File.ObjectKey = "1/new-file"
				file.Thumbnail.ObjectKey = "1/new-thumbnail"
				_, err := db.Exec(`INSERT INTO temp_objects (object_key, expiration_time, user_id, app, purpose)
					VALUES ($1, 1, $3, $4, 'file_upload'), ($2, 1, $3, $4, 'file_upload')`, file.File.ObjectKey, file.Thumbnail.ObjectKey, file.OwnerID, tc.stagedApp)
				require.NoError(t, err)
				if thumbnailOnly {
					ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
					ctx.Request = httptest.NewRequest(http.MethodPut, "/files/thumbnail", nil)
					ctx.Request.Header.Set("X-Auth-User-ID", "1")
					err = controller.UpdateThumbnail(ctx, file.ID, file.Thumbnail, tc.requestApp)
				} else {
					_, err = controller.Update(t.Context(), file.OwnerID, file, tc.requestApp)
				}
				wrongApp := !tc.legacy && tc.app != tc.requestApp
				allowed := !wrongApp && tc.requestApp == tc.stagedApp
				if allowed {
					require.NoError(t, err)
				} else if wrongApp {
					require.ErrorIs(t, err, ente.ErrPermissionDenied)
				} else {
					var apiErr *ente.ApiError
					require.ErrorAs(t, err, &apiErr)
					require.Equal(t, "staged upload not found", apiErr.Message)
				}
				stored, err := controller.ObjectRepo.GetObject(file.ID, ente.THUMBNAIL)
				require.NoError(t, err)
				if allowed {
					require.Equal(t, file.Thumbnail.ObjectKey, stored.ObjectKey)
				} else {
					require.Equal(t, "1/old-thumbnail", stored.ObjectKey)
					var staged int
					require.NoError(t, db.QueryRow(`SELECT COUNT(*) FROM temp_objects`).Scan(&staged))
					require.Equal(t, 2, staged)
				}
			})
		}
	}
}

func TestDuplicateFileRegistrationAppBinding(t *testing.T) {
	for _, tc := range []struct {
		name      string
		app       ente.App
		legacy    bool
		collision bool
	}{
		{name: "photos", app: ente.Photos},
		{name: "wrong app", app: ente.Locker},
		{name: "legacy cross-app", app: ente.Locker, legacy: true},
		{name: "cross-app collision", app: ente.Locker, collision: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			controller, file, db := setupFileUploadBindingTest(t, ente.Photos)
			fileID := file.ID
			if tc.legacy {
				_, err := db.Exec(`UPDATE files SET app = NULL WHERE file_id = $1`, fileID)
				require.NoError(t, err)
			}
			file.ID = 0
			if tc.app == ente.Locker {
				file.CollectionID = insertObjectCleanupTestCollection(t, db, file.OwnerID)
				_, err := db.Exec(`UPDATE collections SET app = 'locker' WHERE collection_id = $1`, file.CollectionID)
				require.NoError(t, err)
			}
			_, err := db.Exec(`UPDATE object_copies SET wasabi = 1`)
			require.NoError(t, err)
			if tc.collision {
				file.File.DecryptionHeader = "replacement-header"
			}
			ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
			ctx.Request = httptest.NewRequest(http.MethodPost, "/files", nil)
			result, err := controller.Create(ctx, file.OwnerID, file, "test", tc.app)
			if tc.collision {
				require.ErrorIs(t, err, ente.ErrBadRequest)
				require.Eventually(t, func() bool {
					var pending int
					err := db.QueryRow(`SELECT COUNT(*) FROM object_copies WHERE wasabi IS NULL`).Scan(&pending)
					return err == nil && pending == 2
				}, 2*time.Second, 10*time.Millisecond)
			} else if tc.legacy || tc.app == ente.Photos {
				require.NoError(t, err)
				require.Equal(t, fileID, result.ID)
			} else {
				require.ErrorIs(t, err, ente.ErrPermissionDenied)
			}
			if !tc.collision {
				var replicated int
				require.NoError(t, db.QueryRow(`SELECT COUNT(*) FROM object_copies WHERE wasabi = 1`).Scan(&replicated))
				require.Equal(t, 2, replicated)
			}
		})
	}
}

func setupFileUploadBindingTest(t *testing.T, app ente.App) (*FileController, ente.File, *sql.DB) {
	t.Helper()
	s3Server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet && r.URL.Query().Has("versions") {
			_, _ = w.Write([]byte(`<ListVersionsResult/>`))
			return
		}
		if r.Method != http.MethodHead {
			t.Errorf("unexpected storage request: %s", r.Method)
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		w.Header().Set("Content-Length", "100")
		if strings.Contains(r.URL.Path, "thumbnail") {
			w.Header().Set("Content-Length", "10")
		}
	}))
	t.Cleanup(s3Server.Close)
	_, repository, db := setupObjectCleanupRaceTest(t, s3Server.URL)
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "file-update-app@ente.com", CreationTime: 1})
	testutil.InsertUsage(t, db, ownerID, 0)
	testutil.InsertSubscription(t, db, testutil.SubscriptionFixture{UserID: ownerID, Storage: 1 << 30, ExpiryTime: time.Now().Add(time.Hour).UnixMicro()})
	collectionID := insertObjectCleanupTestCollection(t, db, ownerID)
	_, err := db.Exec(`UPDATE collections SET app = $1 WHERE collection_id = $2`, app, collectionID)
	require.NoError(t, err)
	file := objectCleanupTestFile(ownerID, collectionID, "1/old-file", "1/old-thumbnail")
	_, err = db.Exec(`INSERT INTO temp_objects (object_key, expiration_time) VALUES ($1, 1), ($2, 1)`, file.File.ObjectKey, file.Thumbnail.ObjectKey)
	require.NoError(t, err)
	file, _, err = repository.Create(file, 100, 10, 110, ownerID, app)
	require.NoError(t, err)
	users := &repo.UserRepository{DB: db}
	return &FileController{
		FileRepo: repository, ObjectRepo: repository.ObjectRepo, S3Config: repository.S3Config,
		CollectionRepo: &repo.CollectionRepository{DB: db, CollectionLinkRepo: &public.CollectionLinkRepo{DB: db}},
		UsageCtrl: &UsageController{UserRepo: users, UsageRepo: &repo.UsageRepository{DB: db}, UploadResultCache: make(map[int64]bool),
			BillingCtrl: &BillingController{UserRepo: users, BillingRepo: &repo.BillingRepository{DB: db}}},
	}, file, db
}
