package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
	"github.com/patrickmn/go-cache"
	"github.com/stretchr/testify/require"
)

func TestShouldCheckCollectionLinkDeviceLimit(t *testing.T) {
	require.True(t, shouldCheckCollectionLinkDeviceLimit("/public-collection/info"))
	require.True(t, shouldCheckCollectionLinkDeviceLimit("/public-collection/diff"))

	require.False(t, shouldCheckCollectionLinkDeviceLimit("/public-collection/files/download/1"))
	require.False(t, shouldCheckCollectionLinkDeviceLimit("/public-collection/upload-url"))
	require.False(t, shouldCheckCollectionLinkDeviceLimit("/public-collection/verify-password"))
}

func TestCollectionLinkCacheIsScopedToOrigin(t *testing.T) {
	const (
		accessToken = "access-token"
		clientIP    = "192.0.2.1"
		userAgent   = "test-agent"
	)
	origins := []string{"https://albums.example", "https://gallery.example"}
	linkCache := cache.New(time.Minute, time.Minute)
	for i, origin := range origins {
		key := computeHashKeyForList([]string{accessToken, clientIP, userAgent, origin}, ":")
		linkCache.Set(key, ente.PublicCollectionSummary{ID: int64(i + 1)}, cache.DefaultExpiration)
	}

	gin.SetMode(gin.TestMode)
	var ids []int64
	router := gin.New()
	middleware := (&CollectionLinkMiddleware{Cache: linkCache}).Authenticate(func(c *gin.Context) string { return c.FullPath() })
	router.GET("/public-collection/files/download/:fileID", middleware, func(c *gin.Context) {
		ids = append(ids, auth.MustGetPublicAccessContext(c).ID)
		c.Status(http.StatusNoContent)
	})
	for _, origin := range origins {
		req := httptest.NewRequest(http.MethodGet, "/public-collection/files/download/1", nil)
		req.RemoteAddr = clientIP + ":1234"
		req.Header.Set("Origin", origin)
		req.Header.Set("User-Agent", userAgent)
		req.Header.Set("X-Auth-Access-Token", accessToken)
		resp := httptest.NewRecorder()
		router.ServeHTTP(resp, req)
		require.Equal(t, http.StatusNoContent, resp.Code)
	}
	require.Equal(t, []int64{1, 2}, ids)
}
