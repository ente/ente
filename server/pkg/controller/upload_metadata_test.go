package controller

import (
	"database/sql"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/stretchr/testify/require"
)

func TestPendingUploadMetadata(t *testing.T) {
	s3Server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || !r.URL.Query().Has("uploads") {
			t.Errorf("unexpected storage request: %s %s", r.Method, r.URL)
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		_, _ = w.Write([]byte(`<InitiateMultipartUploadResult><UploadId>upload-id</UploadId></InitiateMultipartUploadResult>`))
	}))
	t.Cleanup(s3Server.Close)
	cleanup, _, db := setupObjectCleanupRaceTest(t, s3Server.URL)
	userID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1580559962386438, Email: "upload-metadata@ente.com", CreationTime: 1})
	testutil.InsertSubscription(t, db, testutil.SubscriptionFixture{
		UserID: userID, Storage: 10 << 30, ExpiryTime: time.Now().Add(time.Hour).UnixMicro(),
	})
	users := &repo.UserRepository{DB: db}
	controller := &FileController{
		S3Config: cleanup.S3Config, ObjectCleanupCtrl: cleanup,
		UsageCtrl: &UsageController{
			UserRepo: users, UsageRepo: &repo.UsageRepository{DB: db},
			BillingCtrl: &BillingController{UserRepo: users, BillingRepo: &repo.BillingRepository{DB: db}},
		},
	}
	const checksum = "XUFAKrxLKna5cZ2REBfFkg=="
	const client = "io.ente.locker/1.0"
	for _, tc := range []struct {
		name      string
		multipart bool
		legacy    bool
	}{
		{name: "single"},
		{name: "multipart", multipart: true},
		{name: "legacy single", legacy: true},
		{name: "legacy multipart", multipart: true, legacy: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			startedAt := time.Now().UnixMicro()
			var objectKey string
			if tc.multipart {
				var upload ente.MultipartUploadURLs
				var err error
				if tc.legacy {
					upload, err = controller.GetMultipartUploadURLs(t.Context(), userID, 1, ente.Locker, client)
				} else {
					upload, err = controller.GetMultipartUploadURLWithMetadata(t.Context(), userID, ente.MultipartUploadURLRequest{
						ContentLength: ente.MinMultipartUploadSize, PartLength: ente.MinMultipartUploadSize, PartMD5s: []string{checksum},
					}, ente.Locker, client)
				}
				require.NoError(t, err)
				require.Len(t, upload.PartURLs, 1)
				objectKey = upload.ObjectKey
			} else if tc.legacy {
				uploads, err := controller.GetUploadURLs(t.Context(), userID, 1, ente.Locker, false, client)
				require.NoError(t, err)
				objectKey = uploads[0].ObjectKey
			} else {
				upload, err := controller.GetUploadURLWithMetadata(t.Context(), userID, ente.UploadURLRequest{
					ContentLength: 5, ContentMD5: " " + checksum + " ",
				}, ente.Locker, client)
				require.NoError(t, err)
				objectKey = upload.ObjectKey
			}
			var owner, createdAt, expiresAt int64
			var app, purpose, savedClient, bucket string
			var length sql.NullInt64
			var md5, uploadID sql.NullString
			var multipart bool
			require.NoError(t, db.QueryRow(`SELECT user_id, created_at, expiration_time, app, purpose, client,
			    content_length, content_md5, upload_id, is_multipart, bucket_id FROM temp_objects WHERE object_key = $1`, objectKey).
				Scan(&owner, &createdAt, &expiresAt, &app, &purpose, &savedClient, &length, &md5, &uploadID, &multipart, &bucket))
			require.Equal(t, userID, owner)
			require.Equal(t, "locker", app)
			require.Equal(t, "file_upload", purpose)
			require.Equal(t, client, savedClient)
			require.Equal(t, "b2-eu-cen", bucket)
			require.Equal(t, tc.multipart, multipart)
			require.Equal(t, tc.multipart, uploadID.Valid)
			require.Equal(t, !tc.legacy, length.Valid)
			if length.Valid {
				wantLength := int64(5)
				if tc.multipart {
					wantLength = ente.MinMultipartUploadSize
				}
				require.Equal(t, wantLength, length.Int64)
			}
			require.Equal(t, !tc.legacy && !tc.multipart, md5.Valid)
			if md5.Valid {
				require.Equal(t, checksum, md5.String)
			}
			require.GreaterOrEqual(t, createdAt, startedAt)
			require.InDelta(t, (14 * 24 * time.Hour).Microseconds(), expiresAt-createdAt, float64(time.Second.Microseconds()))
			tx, err := db.Begin()
			require.NoError(t, err)
			defer tx.Rollback()
			require.NoError(t, cleanup.Repo.SetExpiryForTempObject(tx, ente.TempObject{ObjectKey: objectKey}, 1))
			var afterRetry int64
			require.NoError(t, tx.QueryRow(`SELECT created_at FROM temp_objects WHERE object_key = $1`, objectKey).Scan(&afterRetry))
			require.Equal(t, createdAt, afterRetry)
		})
	}
}
