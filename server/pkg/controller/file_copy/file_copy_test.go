package file_copy

import (
	"context"
	"database/sql"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/credentials"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/stretchr/testify/require"
)

const (
	copyTestBucket = "test-bucket"
	copyTestDC     = "b2-eu-cen"
)

type recordedCopyRequest struct {
	method     string
	key        string
	uploadID   string
	partNumber string
	copyRange  string
	copySource string
	parts      []completedCopyPart
}

type completedCopyPart struct {
	ETag       string `xml:"ETag"`
	PartNumber int64  `xml:"PartNumber"`
}

type copyRequestRecorder struct {
	mu       sync.Mutex
	requests []recordedCopyRequest
	err      error
}

func (recorder *copyRequestRecorder) record(r *http.Request) bool {
	recorded, err := recordCopyRequest(r)
	recorder.mu.Lock()
	defer recorder.mu.Unlock()
	if err != nil {
		recorder.err = err
		return false
	}
	recorder.requests = append(recorder.requests, recorded)
	return true
}

func (recorder *copyRequestRecorder) result(t *testing.T) []recordedCopyRequest {
	t.Helper()
	recorder.mu.Lock()
	defer recorder.mu.Unlock()
	require.NoError(t, recorder.err)
	return append([]recordedCopyRequest(nil), recorder.requests...)
}

func TestCopyS3ObjectUsesMultipartAboveSingleCopyLimit(t *testing.T) {
	db := setupFileCopyTestDB(t)
	insertTempCopyObjects(t, db, "dest-small", "dest-large")

	var recorder copyRequestRecorder
	s3Server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !recorder.record(r) {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		query := r.URL.Query()
		switch {
		case r.Method == http.MethodPut && !query.Has("uploadId"):
			writeS3XML(w, `<CopyObjectResult><LastModified>2026-01-01T00:00:00Z</LastModified><ETag>"copy"</ETag></CopyObjectResult>`)
		case r.Method == http.MethodPost && query.Has("uploads"):
			writeS3XML(w, `<CreateMultipartUploadResult><Bucket>test-bucket</Bucket><Key>dest-large</Key><UploadId>upload-1</UploadId></CreateMultipartUploadResult>`)
		case r.Method == http.MethodPut:
			writeS3XML(w, fmt.Sprintf(`<CopyPartResult><LastModified>2026-01-01T00:00:00Z</LastModified><ETag>"etag-%s"</ETag></CopyPartResult>`, query.Get("partNumber")))
		case r.Method == http.MethodPost:
			writeS3XML(w, `<CompleteMultipartUploadResult><Bucket>test-bucket</Bucket><Key>dest-large</Key><ETag>"complete"</ETag></CompleteMultipartUploadResult>`)
		default:
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	}))
	t.Cleanup(s3Server.Close)

	client := newFileCopyTestS3Client(t, s3Server.URL)
	objectCleanupRepo := &repo.ObjectCleanupRepository{DB: db}
	bucket := aws.String(copyTestBucket)
	require.NoError(t, copyS3Object(context.Background(), client, bucket, copyTestDC, objectCleanupRepo, &copyS3ObjectReq{
		SourceS3Object: ente.S3ObjectKey{ObjectKey: "source-small", FileSize: maxSingleCopySize, Type: ente.FILE},
		DestObjectKey:  "dest-small",
	}))
	require.NoError(t, copyS3Object(context.Background(), client, bucket, copyTestDC, objectCleanupRepo, &copyS3ObjectReq{
		SourceS3Object: ente.S3ObjectKey{ObjectKey: "source-large", FileSize: maxSingleCopySize + 1, Type: ente.FILE},
		DestObjectKey:  "dest-large",
	}))

	requests := recorder.result(t)
	require.Len(t, requests, 8)
	require.Equal(t, recordedCopyRequest{
		method: http.MethodPut, key: "dest-small", copySource: "test-bucket/source-small",
	}, requests[0])
	require.Equal(t, recordedCopyRequest{
		method: http.MethodPost, key: "dest-large",
	}, requests[1])
	expectedRanges := []string{
		"bytes=0-1073741823",
		"bytes=1073741824-2147483647",
		"bytes=2147483648-3221225471",
		"bytes=3221225472-4294967295",
		"bytes=4294967296-5000000000",
	}
	for i, copyRange := range expectedRanges {
		require.Equal(t, recordedCopyRequest{
			method:     http.MethodPut,
			key:        "dest-large",
			uploadID:   "upload-1",
			partNumber: strconv.Itoa(i + 1),
			copyRange:  copyRange,
			copySource: "test-bucket/source-large",
		}, requests[i+2])
	}
	require.Equal(t, recordedCopyRequest{
		method:   http.MethodPost,
		key:      "dest-large",
		uploadID: "upload-1",
		parts: []completedCopyPart{
			{ETag: `"etag-1"`, PartNumber: 1},
			{ETag: `"etag-2"`, PartNumber: 2},
			{ETag: `"etag-3"`, PartNumber: 3},
			{ETag: `"etag-4"`, PartNumber: 4},
			{ETag: `"etag-5"`, PartNumber: 5},
		},
	}, requests[7])

	assertTempCopyObject(t, db, "dest-small", false, sql.NullString{})
	assertTempCopyObject(t, db, "dest-large", true, sql.NullString{String: "upload-1", Valid: true})
}

func TestMultipartCopyFailureAbortsAndRetainsCleanupState(t *testing.T) {
	db := setupFileCopyTestDB(t)
	insertTempCopyObjects(t, db, "dest-large")
	ctx, cancel := context.WithCancel(context.Background())

	var recorder copyRequestRecorder
	s3Server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !recorder.record(r) {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		query := r.URL.Query()
		switch {
		case r.Method == http.MethodPost && query.Has("uploads"):
			writeS3XML(w, `<CreateMultipartUploadResult><Bucket>test-bucket</Bucket><Key>dest-large</Key><UploadId>upload-1</UploadId></CreateMultipartUploadResult>`)
		case r.Method == http.MethodPut && query.Get("partNumber") == "1":
			writeS3XML(w, `<CopyPartResult><LastModified>2026-01-01T00:00:00Z</LastModified><ETag>"etag-1"</ETag></CopyPartResult>`)
		case r.Method == http.MethodPut:
			cancel()
			w.WriteHeader(http.StatusInternalServerError)
			_, _ = io.WriteString(w, `<Error><Code>InternalError</Code><Message>copy failed</Message></Error>`)
		case r.Method == http.MethodDelete:
			w.WriteHeader(http.StatusNoContent)
		default:
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	}))
	t.Cleanup(s3Server.Close)

	err := copyS3Object(ctx, newFileCopyTestS3Client(t, s3Server.URL), aws.String(copyTestBucket), copyTestDC, &repo.ObjectCleanupRepository{DB: db}, &copyS3ObjectReq{
		SourceS3Object: ente.S3ObjectKey{ObjectKey: "source-large", FileSize: maxSingleCopySize + 1, Type: ente.FILE},
		DestObjectKey:  "dest-large",
	})
	require.Error(t, err)
	requests := recorder.result(t)
	require.Len(t, requests, 4)
	require.Equal(t, http.MethodDelete, requests[3].method)
	require.Equal(t, "upload-1", requests[3].uploadID)
	assertTempCopyObject(t, db, "dest-large", true, sql.NullString{String: "upload-1", Valid: true})
}

func setupFileCopyTestDB(t *testing.T) *sql.DB {
	t.Helper()
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	return db
}

func insertTempCopyObjects(t *testing.T, db *sql.DB, objectKeys ...string) {
	t.Helper()
	for _, objectKey := range objectKeys {
		_, err := db.Exec(`INSERT INTO temp_objects(object_key, expiration_time, bucket_id) VALUES($1, 1, $2)`, objectKey, copyTestDC)
		require.NoError(t, err)
	}
}

func assertTempCopyObject(t *testing.T, db *sql.DB, objectKey string, isMultipart bool, uploadID sql.NullString) {
	t.Helper()
	var actualMultipart bool
	var actualUploadID sql.NullString
	require.NoError(t, db.QueryRow(`SELECT is_multipart, upload_id FROM temp_objects WHERE object_key = $1`, objectKey).Scan(&actualMultipart, &actualUploadID))
	require.Equal(t, isMultipart, actualMultipart)
	require.Equal(t, uploadID, actualUploadID)
}

func newFileCopyTestS3Client(t *testing.T, endpoint string) *s3.S3 {
	t.Helper()
	sess, err := session.NewSession(&aws.Config{
		Credentials:      credentials.NewStaticCredentials("key", "secret", ""),
		Endpoint:         aws.String(endpoint),
		Region:           aws.String("us-east-1"),
		S3ForcePathStyle: aws.Bool(true),
		DisableSSL:       aws.Bool(true),
		MaxRetries:       aws.Int(0),
	})
	require.NoError(t, err)
	return s3.New(sess)
}

func recordCopyRequest(r *http.Request) (recordedCopyRequest, error) {
	recorded := recordedCopyRequest{
		method:     r.Method,
		key:        strings.TrimPrefix(r.URL.Path, "/"+copyTestBucket+"/"),
		uploadID:   r.URL.Query().Get("uploadId"),
		partNumber: r.URL.Query().Get("partNumber"),
		copyRange:  r.Header.Get("X-Amz-Copy-Source-Range"),
		copySource: r.Header.Get("X-Amz-Copy-Source"),
	}
	if r.Method == http.MethodPost && recorded.uploadID != "" {
		body, err := io.ReadAll(r.Body)
		if err != nil {
			return recorded, err
		}
		var completed struct {
			Parts []completedCopyPart `xml:"Part"`
		}
		if err = xml.Unmarshal(body, &completed); err != nil {
			return recorded, err
		}
		recorded.parts = completed.Parts
	}
	return recorded, nil
}

func writeS3XML(w http.ResponseWriter, body string) {
	w.Header().Set("Content-Type", "application/xml")
	_, _ = io.WriteString(w, body)
}
