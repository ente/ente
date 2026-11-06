package controller

import (
	"database/sql"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/gin-gonic/gin"
	"github.com/lib/pq"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

func TestFileDownloadBucketSelection(t *testing.T) {
	b2, wasabi, cold := "b2-eu-cen", "wasabi-eu-central-2-v3", "scw-eu-fr-v3"
	for _, primary := range []string{b2, wasabi} {
		secondary := wasabi
		if primary == wasabi {
			secondary = b2
		}
		controller := &FileController{S3Config: fileDownloadS3Config(t, primary, secondary)}
		for _, tc := range []struct {
			name       string
			dcs        []string
			wantNormal string
			wantCLI    string
		}{
			{"b2_only", []string{b2}, b2, b2},
			{"wasabi_only", []string{wasabi}, wasabi, wasabi},
			{"both", []string{wasabi, cold, b2}, primary, wasabi},
			{"legacy_b2", []string{"wasabi-eu-central-2", "scw-eu-fr", b2}, b2, b2},
			{"cold_only", []string{cold}, "", ""},
			{"obsolete_only", []string{"wasabi-eu-central-2", "scw-eu-fr-locked"}, "", ""},
			{"empty", nil, "", ""},
		} {
			for _, client := range []struct {
				userAgent string
				wantDC    string
			}{
				{"ente", tc.wantNormal},
				{"go-resty/2.0", tc.wantCLI},
			} {
				t.Run(primary+"/"+tc.name+"/"+client.userAgent, func(t *testing.T) {
					object := ente.S3ObjectKey{ObjectKey: "1/file"}
					signedURL, err := controller.getSignedURLFromObjectAndDCs(fileDownloadContext(client.userAgent), object, tc.dcs, ente.FILE)
					if client.wantDC == "" {
						require.ErrorContains(t, err, "no recorded hot storage copy")
						require.NotErrorIs(t, err, sql.ErrNoRows)
						require.Empty(t, signedURL)
						return
					}
					require.NoError(t, err)
					assertFileDownloadURL(t, signedURL, client.wantDC, object.ObjectKey)
				})
			}
		}
	}
}

func TestFileDownloadRecordedLocations(t *testing.T) {
	controller, file, db := setupFileDownloadTest(t)
	b2, wasabi := controller.S3Config.GetHotBackblazeDC(), controller.S3Config.GetHotWasabiDC()
	routes := []struct {
		name string
		sign func(*gin.Context, ente.ObjectType) (string, error)
	}{
		{"owner", func(ctx *gin.Context, objType ente.ObjectType) (string, error) {
			return controller.getSignedURLForAccessibleObject(ctx, file.OwnerID, file.ID, objType)
		}},
		{"shared", func(ctx *gin.Context, objType ente.ObjectType) (string, error) {
			return controller.getSignedURLForAccessibleObject(ctx, 2, file.ID, objType)
		}},
		{"owner_only", func(ctx *gin.Context, objType ente.ObjectType) (string, error) {
			return controller.getSignedURLForOwnedObject(ctx, file.OwnerID, file.ID, objType)
		}},
		{"public_collection_or_cast", func(ctx *gin.Context, objType ente.ObjectType) (string, error) {
			return controller.GetPublicOrCastFileURL(ctx, file.ID, objType, file.CollectionID)
		}},
		{"authorized_public_file", func(ctx *gin.Context, objType ente.ObjectType) (string, error) {
			return controller.GetSignedURLForPublicFile(ctx, file.ID, objType)
		}},
	}
	for _, primary := range []string{b2, wasabi} {
		secondary := wasabi
		if primary == wasabi {
			secondary = b2
		}
		controller.S3Config = fileDownloadS3Config(t, primary, secondary)
		for _, object := range []struct {
			objType ente.ObjectType
			key     string
			dc      string
		}{
			{ente.FILE, file.File.ObjectKey, b2},
			{ente.THUMBNAIL, file.Thumbnail.ObjectKey, wasabi},
			{ente.FILE, file.File.ObjectKey, ""},
			{ente.THUMBNAIL, file.Thumbnail.ObjectKey, ""},
		} {
			dcs := []string{}
			name := string(object.objType)
			if object.dc != "" {
				dcs = append(dcs, object.dc)
			} else {
				name += "_without_hot_copy"
			}
			_, err := db.Exec(`UPDATE object_keys SET datacenters = '{}' WHERE file_id = $1`, file.ID)
			require.NoError(t, err)
			_, err = db.Exec(`UPDATE object_keys SET datacenters = $1 WHERE file_id = $2 AND o_type = $3`, pq.Array(dcs), file.ID, object.objType)
			require.NoError(t, err)
			for _, userAgent := range []string{"ente", "go-resty/2.0"} {
				for _, route := range routes {
					t.Run(primary+"/"+name+"/"+userAgent+"/"+route.name, func(t *testing.T) {
						signedURL, err := route.sign(fileDownloadContext(userAgent), object.objType)
						if object.dc == "" {
							require.ErrorContains(t, err, "no recorded hot storage copy")
							require.NotErrorIs(t, err, sql.ErrNoRows)
							require.Empty(t, signedURL)
							return
						}
						require.NoError(t, err)
						assertFileDownloadURL(t, signedURL, object.dc, object.key)
					})
				}
			}
		}
	}
}

func assertFileDownloadURL(t *testing.T, signedURL, dc, objectKey string) {
	t.Helper()
	parsed, err := url.Parse(signedURL)
	require.NoError(t, err)
	require.Equal(t, dc+".example.test", parsed.Host)
	require.Equal(t, "/"+dc+"/"+objectKey, parsed.Path)
	require.Equal(t, "attachment", parsed.Query().Get("response-content-disposition"))
	require.Equal(t, "application/octet-stream", parsed.Query().Get("response-content-type"))
	require.Equal(t, strconv.Itoa(int(PreSignedRequestValidityDuration.Seconds())), parsed.Query().Get("X-Amz-Expires"))
	require.NotEmpty(t, parsed.Query().Get("X-Amz-Signature"))
}

func TestFileDownloadAuthorization(t *testing.T) {
	for _, tc := range []struct {
		name       string
		actor      int64
		ownerOnly  bool
		collection bool
		mutation   string
	}{
		{name: "unshared_user", actor: 3},
		{name: "shared_user_not_owner", actor: 2, ownerOnly: true},
		{name: "revoked_share", actor: 2, mutation: `UPDATE collection_shares SET is_deleted = TRUE`},
		{name: "deleted_shared_file", actor: 2, mutation: `UPDATE collection_files SET is_deleted = TRUE`},
		{name: "removed_shared_file", actor: 2, mutation: `UPDATE collection_files SET action = 'REMOVE'`},
		{name: "deleted_public_file", collection: true, mutation: `UPDATE collection_files SET is_deleted = TRUE`},
		{name: "removed_public_file", collection: true, mutation: `UPDATE collection_files SET action = 'REMOVE'`},
		{name: "file_outside_collection", collection: true, mutation: `DELETE FROM collection_files`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			controller, file, db := setupFileDownloadTest(t)
			if tc.mutation != "" {
				_, err := db.Exec(tc.mutation)
				require.NoError(t, err)
			}
			for _, userAgent := range []string{"ente", "go-resty/2.0"} {
				for _, objType := range []ente.ObjectType{ente.FILE, ente.THUMBNAIL} {
					ctx := fileDownloadContext(userAgent)
					var signedURL string
					var err error
					switch {
					case tc.collection:
						signedURL, err = controller.GetPublicOrCastFileURL(ctx, file.ID, objType, file.CollectionID)
					case tc.ownerOnly:
						signedURL, err = controller.getSignedURLForOwnedObject(ctx, tc.actor, file.ID, objType)
					default:
						signedURL, err = controller.getSignedURLForAccessibleObject(ctx, tc.actor, file.ID, objType)
					}
					require.ErrorIs(t, err, ente.ErrPermissionDenied)
					require.Empty(t, signedURL)
				}
			}
		})
	}
}

func TestFileDownloadExcludesColdConfiguredBucket(t *testing.T) {
	controller := &FileController{S3Config: fileDownloadS3Config(t, "scw-eu-fr-v3", "b2-eu-cen")}
	for _, userAgent := range []string{"ente", "go-resty/2.0"} {
		signedURL, err := controller.getSignedURLFromObjectAndDCs(fileDownloadContext(userAgent),
			ente.S3ObjectKey{ObjectKey: "1/file"}, []string{"scw-eu-fr-v3"}, ente.FILE)
		require.ErrorContains(t, err, "no recorded hot storage copy")
		require.Empty(t, signedURL)
	}
}

func fileDownloadContext(userAgent string) *gin.Context {
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	ctx.Request = httptest.NewRequest(http.MethodGet, "/files/download/1", nil)
	ctx.Request.Header.Set("User-Agent", userAgent)
	return ctx
}

func fileDownloadS3Config(t *testing.T, primary, secondary string) *s3config.S3Config {
	t.Helper()
	viper.Reset()
	t.Cleanup(viper.Reset)
	viper.Set("s3.hot_storage.primary", primary)
	viper.Set("s3.hot_storage.secondary", secondary)
	viper.Set("s3.use_path_style_urls", true)
	for _, dc := range []string{"b2-eu-cen", "wasabi-eu-central-2-v3", "scw-eu-fr-v3"} {
		viper.Set("s3."+dc+".bucket", dc)
		viper.Set("s3."+dc+".key", "test-key")
		viper.Set("s3."+dc+".secret", "test-secret")
		viper.Set("s3."+dc+".endpoint", "https://"+dc+".example.test")
		viper.Set("s3."+dc+".region", "us-east-1")
	}
	return s3config.NewS3Config()
}

func setupFileDownloadTest(t *testing.T) (*FileController, ente.File, *sql.DB) {
	t.Helper()
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	gin.SetMode(gin.TestMode)
	for _, userID := range []int64{1, 2, 3} {
		testutil.InsertUser(t, db, testutil.UserFixture{UserID: userID, Email: strconv.FormatInt(userID, 10) + "@download.test", CreationTime: 1})
	}
	file := ente.File{OwnerID: 1, File: ente.FileAttributes{ObjectKey: "1/file"}, Thumbnail: ente.FileAttributes{ObjectKey: "1/thumbnail"}}
	require.NoError(t, db.QueryRow(`INSERT INTO files(owner_id, file_decryption_header, thumbnail_decryption_header,
		metadata_decryption_header, encrypted_metadata, updation_time, info)
		VALUES (1, 'file-header', 'thumbnail-header', 'metadata-header', 'metadata', 1, '{}') RETURNING file_id`).Scan(&file.ID))
	require.NoError(t, db.QueryRow(`INSERT INTO collections(owner_id, encrypted_key, key_decryption_nonce, name, type, attributes, updation_time, app)
		VALUES (1, 'key', 'nonce', 'Downloads', 'album', '{}', 1, 'photos') RETURNING collection_id`).Scan(&file.CollectionID))
	_, err := db.Exec(`INSERT INTO collection_files(collection_id, file_id, encrypted_key, key_decryption_nonce, updation_time, c_owner_id, f_owner_id)
		VALUES ($1, $2, 'key', 'nonce', 1, 1, 1)`, file.CollectionID, file.ID)
	require.NoError(t, err)
	_, err = db.Exec(`INSERT INTO collection_shares(collection_id, from_user_id, to_user_id, encrypted_key, updation_time, role_type, shared_at)
		VALUES ($1, 1, 2, 'key', 1, 'VIEWER', 1)`, file.CollectionID)
	require.NoError(t, err)
	_, err = db.Exec(`INSERT INTO object_keys(file_id, o_type, object_key, size, datacenters)
		VALUES ($1, 'file', $2, 100, '{b2-eu-cen,wasabi-eu-central-2-v3}'),
		       ($1, 'thumbnail', $3, 10, '{b2-eu-cen,wasabi-eu-central-2-v3}')`, file.ID, file.File.ObjectKey, file.Thumbnail.ObjectKey)
	require.NoError(t, err)
	return &FileController{
		ObjectRepo: &repo.ObjectRepository{DB: db, LatencySensitiveDB: db},
		S3Config:   fileDownloadS3Config(t, "b2-eu-cen", "wasabi-eu-central-2-v3"),
	}, file, db
}
