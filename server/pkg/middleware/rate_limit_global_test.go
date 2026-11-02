package middleware

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/testutil"
	"github.com/stretchr/testify/require"
)

func TestGlobalRateLimitBucketsAreIndependent(t *testing.T) {
	gin.SetMode(gin.TestMode)
	for _, firstPath := range []string{"/collections", "/files/thumbnail/v3/1"} {
		t.Run(firstPath, func(t *testing.T) {
			rl := NewRateLimitMiddleware(nil, 3, 2, time.Hour)
			t.Cleanup(rl.Stop)
			router := newGlobalRateLimitTestRouter(rl)
			paths := []struct {
				path  string
				limit int
			}{
				{"/collections", 3},
				{"/files/thumbnail/v3/1", 2},
			}
			if firstPath != paths[0].path {
				paths[0], paths[1] = paths[1], paths[0]
			}
			for _, tc := range paths {
				for range tc.limit {
					require.Equal(t, http.StatusNoContent, globalRateLimitTestRequest(router, http.MethodGet, tc.path))
				}
				for range 5 {
					require.Equal(t, http.StatusTooManyRequests, globalRateLimitTestRequest(router, http.MethodGet, tc.path))
				}
			}
		})
	}
}

func TestGlobalRateLimitThumbnailRoutesShareBudget(t *testing.T) {
	gin.SetMode(gin.TestMode)
	rl := &RateLimitMiddleware{limit: 1, thumbnailLimit: 1}
	router := newGlobalRateLimitTestRouter(rl)
	require.Equal(t, http.StatusNoContent, globalRateLimitTestRequest(router, http.MethodGet, "/files/thumbnail/v3/1"))
	for _, route := range []string{
		"/files/preview/:fileID", "/files/preview/v2/:fileID",
		"/public-collection/files/preview/:fileID", "/public-collection/files/thumbnail/v3/:fileID",
		"/public-memory/files/preview/:fileID", "/public-memory/files/thumbnail/v3/:fileID",
		"/cast/files/preview/:fileID", "/cast/files/thumbnail/v3/:fileID",
		"/file-link/thumbnail", "/file-link/thumbnail/v3",
	} {
		router.GET(route, func(c *gin.Context) { c.Status(http.StatusNoContent) })
		path := strings.ReplaceAll(route, ":fileID", "2")
		require.Equal(t, http.StatusTooManyRequests, globalRateLimitTestRequest(router, http.MethodGet, path), route)
	}
	require.Equal(t, http.StatusNoContent, globalRateLimitTestRequest(router, http.MethodGet, "/collections"))
}

func TestGlobalRateLimitOtherRoutesRetainGeneralBudget(t *testing.T) {
	gin.SetMode(gin.TestMode)
	for _, tc := range []struct{ method, path string }{
		{http.MethodGet, "/files/download/1"},
		{http.MethodGet, "/files/data/preview"},
		{http.MethodPut, "/files/thumbnail"},
		{http.MethodPost, "/files/thumbnail/v3/1"},
		{http.MethodGet, "/files/thumbnail/unknown/1"},
		{http.MethodOptions, "/files/thumbnail/v3/1"},
	} {
		t.Run(tc.method+tc.path, func(t *testing.T) {
			rl := &RateLimitMiddleware{limit: 1, thumbnailLimit: 1}
			router := newGlobalRateLimitTestRouter(rl)
			router.GET("/files/download/:fileID", func(c *gin.Context) { c.Status(http.StatusNoContent) })
			router.GET("/files/data/preview", func(c *gin.Context) { c.Status(http.StatusNoContent) })
			router.PUT("/files/thumbnail", func(c *gin.Context) { c.Status(http.StatusNoContent) })
			require.Equal(t, http.StatusNoContent, globalRateLimitTestRequest(router, http.MethodGet, "/collections"))
			require.Equal(t, http.StatusTooManyRequests, globalRateLimitTestRequest(router, tc.method, tc.path))
			require.Equal(t, http.StatusNoContent, globalRateLimitTestRequest(router, http.MethodGet, "/files/thumbnail/v3/1"))
		})
	}
}

func TestGlobalRateLimitResetsBothBuckets(t *testing.T) {
	gin.SetMode(gin.TestMode)
	rl := NewRateLimitMiddleware(nil, 1, 1, time.Hour)
	t.Cleanup(rl.Stop)
	router := newGlobalRateLimitTestRouter(rl)
	for _, path := range []string{"/collections", "/files/thumbnail/v3/1"} {
		require.Equal(t, http.StatusNoContent, globalRateLimitTestRequest(router, http.MethodGet, path))
		require.Equal(t, http.StatusTooManyRequests, globalRateLimitTestRequest(router, http.MethodGet, path))
	}
	rl.ticker.Reset(time.Millisecond)
	require.Eventually(t, func() bool {
		return atomic.LoadInt64(&rl.count) == 0 && atomic.LoadInt64(&rl.thumbnailCount) == 0
	}, time.Second, time.Millisecond)
	for _, path := range []string{"/collections", "/files/thumbnail/v3/1"} {
		require.Equal(t, http.StatusNoContent, globalRateLimitTestRequest(router, http.MethodGet, path))
	}
}

func TestGlobalRateLimitConcurrentRequests(t *testing.T) {
	gin.SetMode(gin.TestMode)
	rl := &RateLimitMiddleware{limit: 10, thumbnailLimit: 20}
	router := newGlobalRateLimitTestRouter(rl)
	var accepted [2]int64
	var wg sync.WaitGroup
	for i, path := range []string{"/collections", "/files/thumbnail/v3/1"} {
		for range 50 {
			wg.Add(1)
			go func() {
				defer wg.Done()
				if globalRateLimitTestRequest(router, http.MethodGet, path) == http.StatusNoContent {
					atomic.AddInt64(&accepted[i], 1)
				}
			}()
		}
	}
	wg.Wait()
	require.Equal(t, [2]int64{10, 20}, accepted)
}

func TestGlobalRateLimitRejectionMetricsIdentifyBucket(t *testing.T) {
	gin.SetMode(gin.TestMode)
	rl := &RateLimitMiddleware{}
	router := newGlobalRateLimitTestRouter(rl)
	for _, tc := range []struct{ path, label string }{
		{"/collections", processGlobalRateLimitURL},
		{"/files/thumbnail/v3/1", processThumbnailRateLimitURL},
	} {
		counter := rateLimitRejections.WithLabelValues(string(rateLimitScopeProcessGlobal), http.MethodGet, tc.label)
		before := testutil.ToFloat64(counter)
		require.Equal(t, http.StatusTooManyRequests, globalRateLimitTestRequest(router, http.MethodGet, tc.path))
		require.Equal(t, before+1, testutil.ToFloat64(counter))
	}
}

func newGlobalRateLimitTestRouter(rl *RateLimitMiddleware) *gin.Engine {
	router := gin.New()
	router.Use(rl.GlobalRateLimiter())
	for _, path := range []string{"/collections", "/files/thumbnail/v3/:fileID"} {
		router.GET(path, func(c *gin.Context) { c.Status(http.StatusNoContent) })
	}
	return router
}

func globalRateLimitTestRequest(router *gin.Engine, method, path string) int {
	response := httptest.NewRecorder()
	router.ServeHTTP(response, httptest.NewRequest(method, path, nil))
	return response.Code
}
