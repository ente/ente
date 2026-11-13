package controller

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"sync/atomic"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go/aws/awserr"
	"github.com/aws/aws-sdk-go/aws/request"
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

func TestUploadFailoverRegistrationProgress(t *testing.T) {
	for _, primary := range []string{fileBucketB2, fileBucketWasabi} {
		for _, bucket := range []string{fileBucketB2, fileBucketWasabi} {
			for _, operation := range []string{"create", "replace", "replace thumbnail", "thumbnail endpoint"} {
				t.Run(primary+"/"+bucket+"/"+operation, func(t *testing.T) {
					test := newFileBucketTest(t)
					initialBucket := primary
					if operation == "create" {
						initialBucket = bucket
					}
					file := test.newFile(t, initialBucket, initialBucket)
					if operation != "create" {
						var err error
						file, err = test.controller.Create(fileBucketContext(http.MethodPost), file.OwnerID, file, "test", ente.Photos)
						require.NoError(t, err)
						if operation == "replace" {
							file.File.ObjectKey = test.upload(t, bucket, 100)
						}
						file.Thumbnail.ObjectKey = test.upload(t, bucket, 10)
					}
					test.switchBucket(primary)
					config := test.controller.S3Config
					start := time.Now()
					for i := range 20 {
						config.RecordUploadActivity(start.Add(time.Duration(i) * 6 * time.Second))
					}
					var err error
					switch operation {
					case "create":
						_, err = test.controller.Create(fileBucketContext(http.MethodPost), file.OwnerID, file, "test", ente.Photos)
					case "thumbnail endpoint":
						err = test.controller.UpdateThumbnail(fileBucketContext(http.MethodPut), file.ID, file.Thumbnail, ente.Photos)
					default:
						_, err = test.controller.Update(t.Context(), file.OwnerID, file, ente.Photos)
					}
					require.NoError(t, err)
					config.RecordUploadActivity(start.Add(2 * time.Minute))
					require.Equal(t, bucket != primary, config.HasHotStorageFailedOver())
				})
			}
		}
	}
}

func TestMultipartUploadFailureClassification(t *testing.T) {
	test := newFileBucketTest(t)
	var cancelDuringInitiation atomic.Bool
	initiationStarted := make(chan struct{})
	storage := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || !r.URL.Query().Has("uploads") {
			t.Errorf("unexpected storage request: %s %s", r.Method, r.URL)
		}
		if cancelDuringInitiation.Swap(false) {
			close(initiationStarted)
			<-r.Context().Done()
			return
		}
		w.WriteHeader(http.StatusServiceUnavailable)
		_, _ = w.Write([]byte(`<Error><Code>ServiceUnavailable</Code><Message>storage unavailable</Message></Error>`))
	}))
	t.Cleanup(storage.Close)
	viper.Set("s3."+fileBucketB2+".endpoint", storage.URL)
	test.switchBucket(fileBucketB2)
	req := ente.MultipartUploadURLRequest{ContentLength: 5, PartLength: 5}
	for _, tc := range []struct {
		name      string
		invalid   bool
		cancelled bool
	}{
		{name: "provider failure"},
		{name: "validation", invalid: true},
		{name: "cancelled", cancelled: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ctx := t.Context()
			if tc.cancelled {
				var cancel context.CancelFunc
				ctx, cancel = context.WithCancel(ctx)
				defer cancel()
				cancelDuringInitiation.Store(true)
				go func() {
					select {
					case <-initiationStarted:
						cancel()
					case <-ctx.Done():
					}
				}()
			}
			input := req
			if tc.invalid {
				input.ContentLength = 0
			}
			_, err := test.controller.GetMultipartUploadURLWithMetadata(ctx, 1, input, ente.Photos, "test")
			require.Error(t, err)
			var initiationError *s3config.MultipartInitiationError
			if tc.invalid {
				require.False(t, errors.As(err, &initiationError))
			} else if tc.cancelled {
				require.ErrorAs(t, err, &initiationError)
				var storageErr awserr.Error
				require.ErrorAs(t, err, &storageErr)
				require.Equal(t, request.CanceledErrorCode, storageErr.Code())
			} else {
				require.ErrorAs(t, err, &initiationError)
				var storageErr awserr.RequestFailure
				require.ErrorAs(t, err, &storageErr)
				require.Equal(t, http.StatusServiceUnavailable, storageErr.StatusCode())
			}
		})
	}
}
