package api

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
	"maps"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go/aws/credentials"
	"github.com/aws/aws-sdk-go/aws/signer/v4"
	"github.com/ente/museum/ente"
	filedata "github.com/ente/museum/ente/filedata"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/controller/access"
	filedatactrl "github.com/ente/museum/pkg/controller/filedata"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/gin-gonic/gin"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

const (
	previewUploadPath          = "/files/data/preview-upload-url"
	multipartPreviewUploadPath = "/files/data/multipart-preview-upload-url"
	previewChecksum            = "XUFAKrxLKna5cZ2REBfFkg=="
	previewFinalPartChecksum   = "fXkwN6B2AYZXSwKC8vQ15w=="
)

func TestPreviewUploadRejectsInvalidMetadata(t *testing.T) {
	router := previewUploadRouter(&FileHandler{FileDataCtrl: &filedatactrl.Controller{}})
	for _, multipart := range []bool{false, true} {
		path, valid := previewUploadBody(1, ente.PreviewVideo, multipart)
		for _, tc := range []struct {
			name  string
			field string
			value any
		}{
			{"missing file ID", "fileID", nil},
			{"negative file ID", "fileID", -1},
			{"missing type", "type", nil},
			{"unsupported type", "type", "file"},
			{"missing length", "contentLength", nil},
			{"negative length", "contentLength", -1},
		} {
			t.Run(fmt.Sprintf("multipart=%t/%s", multipart, tc.name), func(t *testing.T) {
				body := maps.Clone(valid)
				body[tc.field] = tc.value
				rec := performPreviewUpload(t, router, http.MethodPost, path, 1, body)
				require.Equal(t, http.StatusBadRequest, rec.Code, rec.Body.String())
			})
		}
	}
	for _, tc := range []struct {
		name      string
		multipart bool
		field     string
		value     any
	}{
		{"single too large", false, "contentLength", int64(5<<30) + 1},
		{"missing checksum", false, "contentMD5", nil},
		{"malformed checksum", false, "contentMD5", "not-md5"},
		{"wrong digest size", false, "contentMD5", "aGVsbG8="},
		{"checksum newline", false, "contentMD5", previewChecksum + "\n"},
		{"missing part length", true, "partLength", nil},
		{"negative part length", true, "partLength", -1},
		{"part too small", true, "partLength", (5 << 20) - 1},
		{"part too large", true, "partLength", int64(5<<30) + 1},
		{"multipart too large", true, "contentLength", int64(10<<30) + 1},
		{"missing part checksums", true, "partMd5s", nil},
		{"empty part checksums", true, "partMd5s", []string{}},
		{"too few checksums", true, "partMd5s", []string{previewChecksum}},
		{"too many checksums", true, "partMd5s", []string{previewChecksum, previewChecksum, previewChecksum}},
		{"invalid final checksum", true, "partMd5s", []string{previewChecksum, "invalid"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			path, body := previewUploadBody(1, ente.PreviewVideo, tc.multipart)
			body[tc.field] = tc.value
			rec := performPreviewUpload(t, router, http.MethodPost, path, 1, body)
			require.Equal(t, http.StatusBadRequest, rec.Code, rec.Body.String())
		})
	}
}

func TestPreviewUploadMetadataAndLegacyCompatibility(t *testing.T) {
	router, db, userID, fileID := setupPreviewUploadTest(t)
	for _, tc := range []struct {
		name       string
		objectType ente.ObjectType
		multipart  bool
		legacy     bool
	}{
		{name: "single image", objectType: ente.PreviewImage},
		{name: "single video", objectType: ente.PreviewVideo},
		{name: "multipart image", objectType: ente.PreviewImage, multipart: true},
		{name: "multipart video", objectType: ente.PreviewVideo, multipart: true},
		{name: "legacy single", objectType: ente.PreviewVideo, legacy: true},
		{name: "legacy multipart", objectType: ente.PreviewVideo, multipart: true, legacy: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			path, body := previewUploadBody(fileID, tc.objectType, tc.multipart)
			method := http.MethodPost
			if tc.legacy {
				method = http.MethodGet
				path = fmt.Sprintf("%s?fileID=%d&type=%s", previewUploadPath, fileID, tc.objectType)
				if tc.multipart {
					path += "&isMultiPart=true&count=2"
				}
				body = nil
			}
			rec := performPreviewUpload(t, router, method, path, userID, body)
			require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
			var upload filedata.PreviewUploadUrl
			require.NoError(t, json.Unmarshal(rec.Body.Bytes(), &upload))
			require.NotEmpty(t, upload.ObjectID)
			objectKey := filedata.ObjectKey(fileID, userID, tc.objectType, &upload.ObjectID)
			var length sql.NullInt64
			var checksum, uploadID sql.NullString
			var owner int64
			var bucket, app, purpose string
			var multipart bool
			require.NoError(t, db.QueryRow(`SELECT user_id, bucket_id, app, purpose, content_length,
				    content_md5, is_multipart, upload_id FROM temp_objects WHERE object_key = $1`, objectKey).
				Scan(&owner, &bucket, &app, &purpose, &length, &checksum, &multipart, &uploadID))
			require.Equal(t, userID, owner)
			require.Equal(t, "b5", bucket)
			require.Equal(t, "photos", app)
			require.Equal(t, string(tc.objectType), purpose)
			require.Equal(t, tc.multipart, multipart)
			require.Equal(t, !tc.legacy, length.Valid)
			require.Equal(t, !tc.legacy && !tc.multipart, checksum.Valid)
			if !tc.legacy {
				require.Equal(t, body["contentLength"], length.Int64)
			}
			if tc.multipart {
				require.Nil(t, upload.Url)
				require.NotNil(t, upload.PartURLs)
				require.Len(t, *upload.PartURLs, 2)
				require.NotNil(t, upload.CompleteURL)
				require.Equal(t, "preview-upload", uploadID.String)
				complete, err := url.Parse(*upload.CompleteURL)
				require.NoError(t, err)
				require.Equal(t, "/preview-bucket/"+objectKey, complete.Path)
				require.Equal(t, uploadID.String, complete.Query().Get("uploadId"))
				for i, partURL := range *upload.PartURLs {
					part, err := url.Parse(partURL)
					require.NoError(t, err)
					require.Equal(t, strconv.Itoa(i+1), part.Query().Get("partNumber"))
					require.Equal(t, complete.Path, part.Path)
					if tc.legacy {
						require.Equal(t, "host", part.Query().Get("X-Amz-SignedHeaders"))
					} else {
						lengths := []int64{5 << 20, 3}
						checksums := []string{previewChecksum, previewFinalPartChecksum}
						assertPreviewUploadSignature(t, partURL, lengths[i], checksums[i])
					}
				}
			} else {
				require.NotNil(t, upload.Url)
				require.Nil(t, upload.PartURLs)
				require.Nil(t, upload.CompleteURL)
				require.False(t, uploadID.Valid)
				parsed, err := url.Parse(*upload.Url)
				require.NoError(t, err)
				require.Equal(t, "/preview-bucket/"+objectKey, parsed.Path)
				if tc.legacy {
					require.Equal(t, "host", parsed.Query().Get("X-Amz-SignedHeaders"))
				} else {
					require.Equal(t, previewChecksum, checksum.String)
					assertPreviewUploadSignature(t, *upload.Url, 5, previewChecksum)
				}
			}
		})
	}
}

func TestPreviewUploadRequiresOwnedActiveFile(t *testing.T) {
	router, db, ownerID, fileID := setupPreviewUploadTest(t)
	for _, multipart := range []bool{false, true} {
		path, body := previewUploadBody(fileID, ente.PreviewVideo, multipart)
		rec := performPreviewUpload(t, router, http.MethodPost, path, ownerID+1, body)
		require.Equal(t, http.StatusForbidden, rec.Code, rec.Body.String())
	}
	_, err := db.Exec("UPDATE collection_files SET is_deleted = true WHERE file_id = $1", fileID)
	require.NoError(t, err)
	for _, multipart := range []bool{false, true} {
		path, body := previewUploadBody(fileID, ente.PreviewVideo, multipart)
		rec := performPreviewUpload(t, router, http.MethodPost, path, ownerID, body)
		require.Equal(t, http.StatusNotFound, rec.Code, rec.Body.String())
	}
	var count int
	require.NoError(t, db.QueryRow("SELECT count(*) FROM temp_objects").Scan(&count))
	require.Zero(t, count)
}

func previewUploadBody(fileID int64, objectType ente.ObjectType, multipart bool) (string, map[string]any) {
	body := map[string]any{"fileID": fileID, "type": objectType, "contentLength": int64(5)}
	if multipart {
		body["contentLength"] = int64(5<<20) + 3
		body["partLength"] = int64(5 << 20)
		body["partMd5s"] = []string{previewChecksum, previewFinalPartChecksum}
		return multipartPreviewUploadPath, body
	}
	body["contentMD5"] = previewChecksum
	return previewUploadPath, body
}

func previewUploadRouter(h *FileHandler) *gin.Engine {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.GET(previewUploadPath, h.GetPreviewUploadURL)
	router.POST(previewUploadPath, h.GetPreviewUploadURLV2)
	router.POST(multipartPreviewUploadPath, h.GetMultipartPreviewUploadURL)
	return router
}

func performPreviewUpload(t *testing.T, router *gin.Engine, method, path string, userID int64, body map[string]any) *httptest.ResponseRecorder {
	t.Helper()
	encoded, err := json.Marshal(body)
	require.NoError(t, err)
	req := httptest.NewRequest(method, path, bytes.NewReader(encoded))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Auth-User-ID", strconv.FormatInt(userID, 10))
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, req)
	return recorder
}

func assertPreviewUploadSignature(t *testing.T, rawURL string, length int64, checksum string) {
	t.Helper()
	req, err := http.NewRequest(http.MethodPut, rawURL, nil)
	require.NoError(t, err)
	query := req.URL.Query()
	require.Equal(t, "content-length;content-md5;host", query.Get("X-Amz-SignedHeaders"))
	signedAt, err := time.Parse("20060102T150405Z", query.Get("X-Amz-Date"))
	require.NoError(t, err)
	expires, err := strconv.Atoi(query.Get("X-Amz-Expires"))
	require.NoError(t, err)
	signature := query.Get("X-Amz-Signature")
	query.Del("X-Amz-Signature")
	req.URL.RawQuery = query.Encode()
	req.ContentLength = length
	req.Header.Set("Content-Length", strconv.FormatInt(length, 10))
	req.Header.Set("Content-MD5", checksum)
	signer := v4.NewSigner(credentials.NewStaticCredentials("test-key", "test-secret", ""))
	signer.DisableURIPathEscaping = true
	_, err = signer.Presign(req, nil, "s3", "us-east-1", time.Duration(expires)*time.Second, signedAt)
	require.NoError(t, err)
	require.Equal(t, signature, req.URL.Query().Get("X-Amz-Signature"), "signature must bind the expected length and checksum")
}

func setupPreviewUploadTest(t *testing.T) (*gin.Engine, *sql.DB, int64, int64) {
	t.Helper()
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	storage := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || !r.URL.Query().Has("uploads") {
			t.Errorf("unexpected storage request: %s %s", r.Method, r.URL)
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		_, _ = w.Write([]byte(`<InitiateMultipartUploadResult><UploadId>preview-upload</UploadId></InitiateMultipartUploadResult>`))
	}))
	t.Cleanup(storage.Close)
	viper.Reset()
	t.Cleanup(viper.Reset)
	viper.Set("s3.derived-storage", "b5")
	viper.Set("s3.b5.key", "test-key")
	viper.Set("s3.b5.secret", "test-secret")
	viper.Set("s3.b5.endpoint", storage.URL)
	viper.Set("s3.b5.region", "us-east-1")
	viper.Set("s3.b5.bucket", "preview-bucket")
	viper.Set("s3.b5.disable_ssl", true)
	viper.Set("s3.use_path_style_urls", true)
	s3Config := s3config.NewS3Config()
	files := &repo.FileRepository{DB: db}
	collections := &repo.CollectionRepository{DB: db}
	h := &FileHandler{FileDataCtrl: &filedatactrl.Controller{
		FileRepo: files, CollectionRepo: collections, S3Config: s3Config,
		AccessCtrl:              access.NewAccessController(collections, files),
		ObjectCleanupController: &controller.ObjectCleanupController{Repo: &repo.ObjectCleanupRepository{DB: db}},
	}}
	userID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "preview-upload@ente.com", CreationTime: 1})
	var fileID, collectionID int64
	require.NoError(t, db.QueryRow(`INSERT INTO files(owner_id, file_decryption_header, thumbnail_decryption_header,
	    metadata_decryption_header, encrypted_metadata, updation_time, info)
	    VALUES($1, 'header', 'header', 'header', 'metadata', 1, '{}') RETURNING file_id`, userID).Scan(&fileID))
	require.NoError(t, db.QueryRow(`INSERT INTO collections(owner_id, encrypted_key, key_decryption_nonce, name, type, attributes, updation_time, app)
	    VALUES($1, 'key', 'nonce', 'Previews', 'album', '{}', 1, 'photos') RETURNING collection_id`, userID).Scan(&collectionID))
	_, err := db.Exec(`INSERT INTO collection_files(collection_id, file_id, encrypted_key, key_decryption_nonce, updation_time, c_owner_id, f_owner_id)
	    VALUES($1, $2, 'key', 'nonce', 1, $3, $3)`, collectionID, fileID, userID)
	require.NoError(t, err)
	return previewUploadRouter(h), db, userID, fileID
}
