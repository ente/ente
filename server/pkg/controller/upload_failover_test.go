package controller

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"sync/atomic"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

func TestMultipartUploadDuringHotStorageFailover(t *testing.T) {
	for _, primary := range []string{fileBucketB2, fileBucketWasabi} {
		for _, legacy := range []bool{false, true} {
			name := primary + "/metadata"
			if legacy {
				name = primary + "/legacy"
			}
			t.Run(name, func(t *testing.T) {
				var currentConfig atomic.Pointer[s3config.S3Config]
				storage := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					if r.Method != http.MethodPost || !r.URL.Query().Has("uploads") {
						t.Errorf("unexpected storage request: %s %s", r.Method, r.URL)
						w.WriteHeader(http.StatusBadRequest)
						return
					}
					if !currentConfig.Load().FailoverHotStorage() {
						t.Error("expected failover during multipart initiation")
					}
					_, _ = w.Write([]byte(`<InitiateMultipartUploadResult><UploadId>upload-id</UploadId></InitiateMultipartUploadResult>`))
				}))
				t.Cleanup(storage.Close)
				cleanup, _, db := setupObjectCleanupRaceTest(t, storage.URL)
				secondary := fileBucketWasabi
				if primary == secondary {
					secondary = fileBucketB2
				}
				viper.Set("s3.hot_storage.primary", primary)
				viper.Set("s3.hot_storage.secondary", secondary)
				for _, dc := range []string{primary, secondary} {
					for field, value := range map[string]string{
						"key": "test-key", "secret": "test-secret", "endpoint": storage.URL,
						"region": "us-east-1", "bucket": dc,
					} {
						viper.Set("s3."+dc+"."+field, value)
					}
				}
				config := s3config.NewS3Config()
				currentConfig.Store(config)
				cleanup.S3Config = config
				userID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "upload-failover@ente.com", CreationTime: 1})
				testutil.InsertSubscription(t, db, testutil.SubscriptionFixture{
					UserID: userID, Storage: 1 << 30, ExpiryTime: time.Now().Add(time.Hour).UnixMicro(),
				})
				users := &repo.UserRepository{DB: db}
				controller := &FileController{
					S3Config: config, ObjectCleanupCtrl: cleanup,
					UsageCtrl: &UsageController{
						UserRepo: users, UsageRepo: &repo.UsageRepository{DB: db},
						BillingCtrl: &BillingController{UserRepo: users, BillingRepo: &repo.BillingRepository{DB: db}},
					},
				}
				var upload ente.MultipartUploadURLs
				var err error
				if legacy {
					upload, err = controller.GetMultipartUploadURLs(t.Context(), userID, 2, ente.Locker, "test")
				} else {
					upload, err = controller.GetMultipartUploadURLWithMetadata(t.Context(), userID, ente.MultipartUploadURLRequest{
						ContentLength: (5 << 20) + 1, PartLength: 5 << 20,
					}, ente.Locker, "test")
				}
				require.NoError(t, err)
				require.Equal(t, secondary, config.GetHotDataCenter())
				require.Len(t, upload.PartURLs, 2)
				for _, signedURL := range append(upload.PartURLs, upload.CompleteURL) {
					parsed, err := url.Parse(signedURL)
					require.NoError(t, err)
					require.Equal(t, "/"+primary+"/"+upload.ObjectKey, parsed.Path)
					require.Equal(t, "upload-id", parsed.Query().Get("uploadId"))
				}
				bucket, err := cleanup.Repo.GetFileUploadBucket(t.Context(), upload.ObjectKey, userID, ente.Locker)
				require.NoError(t, err)
				require.Equal(t, primary, bucket)

				next, err := controller.GetUploadURLWithMetadata(t.Context(), userID, ente.UploadURLRequest{
					ContentLength: 5, ContentMD5: "XUFAKrxLKna5cZ2REBfFkg==",
				}, ente.Locker, "test")
				require.NoError(t, err)
				parsed, err := url.Parse(next.URL)
				require.NoError(t, err)
				require.Equal(t, "/"+secondary+"/"+next.ObjectKey, parsed.Path)
				bucket, err = cleanup.Repo.GetFileUploadBucket(t.Context(), next.ObjectKey, userID, ente.Locker)
				require.NoError(t, err)
				require.Equal(t, secondary, bucket)
			})
		}
	}
}
