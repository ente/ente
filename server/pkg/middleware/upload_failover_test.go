package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"testing/synctest"
	"time"

	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/testutil"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

func TestUploadFailoverRoutes(t *testing.T) {
	for _, primary := range []string{"b2-eu-cen", "wasabi-eu-central-2-v3"} {
		for _, route := range []struct{ method, path string }{
			{http.MethodPost, "/files/upload-url"},
			{http.MethodPost, "/files/multipart-upload-url"},
		} {
			t.Run(primary+route.path, func(t *testing.T) {
				synctest.Test(t, func(t *testing.T) {
					config := uploadFailoverConfig(t, primary)
					_, secondary := config.GetHotDataCenters()
					counter := hotStorageFailovers.WithLabelValues(primary, secondary)
					before := testutil.ToFloat64(counter)
					router := gin.New()
					router.Use(UploadFailover(config))
					router.Handle(route.method, route.path, func(c *gin.Context) { c.Status(http.StatusOK) })
					for i := range 21 {
						if i > 0 {
							time.Sleep(6 * time.Second)
						}
						require.Equal(t, primary, config.GetHotDataCenter())
						router.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(route.method, route.path, nil))
					}
					require.Equal(t, secondary, config.GetHotDataCenter())
					for range 30 {
						time.Sleep(6 * time.Second)
						router.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(route.method, route.path, nil))
					}
					require.Equal(t, secondary, config.GetHotDataCenter())
					require.Equal(t, before+1, testutil.ToFloat64(counter))
				})
			})
		}
	}
}

func TestUploadFailoverCountsFileArrivals(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		config := uploadFailoverConfig(t, "b2-eu-cen")
		router := gin.New()
		router.Use(UploadFailover(config))
		router.POST("/files/upload-url", func(c *gin.Context) { c.Status(http.StatusOK) })
		release := make(chan struct{})
		router.POST("/files", func(c *gin.Context) {
			<-release
			c.Status(http.StatusInternalServerError)
		})
		for range 20 {
			router.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodPost, "/files/upload-url", nil))
			time.Sleep(6 * time.Second)
		}
		go router.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodPost, "/files", nil))
		synctest.Wait()
		router.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodPost, "/files/upload-url", nil))
		require.False(t, config.HasHotStorageFailedOver())
		close(release)
		synctest.Wait()
		for range 19 {
			time.Sleep(6 * time.Second)
			router.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodPost, "/files/upload-url", nil))
			require.False(t, config.HasHotStorageFailedOver())
		}
		time.Sleep(6 * time.Second)
		router.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodPost, "/files/upload-url", nil))
		require.True(t, config.HasHotStorageFailedOver())
	})
}

func TestUploadFailoverIgnoresOtherTraffic(t *testing.T) {
	for _, tc := range []struct {
		name, method, path string
		status             int
		missingCredentials bool
	}{
		{name: "legacy upload URLs", method: http.MethodGet, path: "/files/upload-urls", status: http.StatusOK},
		{name: "legacy multipart upload URLs", method: http.MethodGet, path: "/files/multipart-upload-urls", status: http.StatusOK},
		{name: "failed URL issuance", method: http.MethodPost, path: "/files/upload-url", status: http.StatusServiceUnavailable},
		{name: "download traffic", method: http.MethodGet, path: "/files/download/1", status: http.StatusOK},
		{name: "preview uploads", method: http.MethodPost, path: "/files/data/preview-upload-url", status: http.StatusOK},
		{name: "missing credentials", method: http.MethodPost, path: "/files/upload-url", status: http.StatusOK, missingCredentials: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			synctest.Test(t, func(t *testing.T) {
				config := uploadFailoverConfig(t, "b2-eu-cen")
				if tc.missingCredentials {
					viper.Set("s3.wasabi-eu-central-2-v3.secret", "")
					config = s3config.NewS3Config()
				}
				router := gin.New()
				router.Use(UploadFailover(config))
				router.Handle(tc.method, tc.path, func(c *gin.Context) { c.Status(tc.status) })
				for range 30 {
					router.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(tc.method, tc.path, nil))
					time.Sleep(6 * time.Second)
				}
				require.False(t, config.HasHotStorageFailedOver())
			})
		})
	}
}

func TestUploadFailoverRequiresSustainedActivity(t *testing.T) {
	for _, tc := range []struct {
		name     string
		interval time.Duration
		requests int
	}{
		{"brief burst", time.Second, 100},
		{"too few requests", 30 * time.Second, 10},
		{"idle gaps", 31 * time.Second, 30},
	} {
		t.Run(tc.name, func(t *testing.T) {
			config := uploadFailoverConfig(t, "b2-eu-cen")
			detector := &uploadFailover{config: config}
			start := time.Now()
			for i := range tc.requests {
				detector.recordUpload(start.Add(time.Duration(i) * tc.interval))
			}
			require.False(t, config.HasHotStorageFailedOver())
		})
	}
}

func uploadFailoverConfig(t *testing.T, primary string) *s3config.S3Config {
	t.Helper()
	viper.Reset()
	t.Cleanup(viper.Reset)
	secondary := "wasabi-eu-central-2-v3"
	if primary == secondary {
		secondary = "b2-eu-cen"
	}
	viper.Set("s3.hot_storage.primary", primary)
	viper.Set("s3.hot_storage.secondary", secondary)
	for _, dc := range []string{primary, secondary} {
		for field, value := range map[string]string{
			"key": "test-key", "secret": "test-secret", "bucket": dc,
			"endpoint": "https://" + dc + ".example.test", "region": "us-east-1",
		} {
			viper.Set("s3."+dc+"."+field, value)
		}
	}
	return s3config.NewS3Config()
}
