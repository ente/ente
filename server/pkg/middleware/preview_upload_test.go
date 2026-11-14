package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/ente/museum/pkg/controller/discord"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestPreviewUploadRateLimits(t *testing.T) {
	gin.SetMode(gin.TestMode)
	rateLimiter := NewRateLimitMiddleware(discord.NewDiscordController(nil, "test", "test"), 1000, 1000, time.Minute)
	t.Cleanup(rateLimiter.Stop)
	router := gin.New()
	router.Use(rateLimiter.APIRateLimitForUserMiddleware(func(c *gin.Context) string {
		return c.FullPath()
	}))
	for _, route := range []struct{ method, path string }{
		{http.MethodGet, "/files/data/preview-upload-url"},
		{http.MethodPost, "/files/data/preview-upload-url"},
		{http.MethodPost, "/files/data/multipart-preview-upload-url"},
	} {
		router.Handle(route.method, route.path, func(c *gin.Context) {
			c.Status(http.StatusNoContent)
		})
	}
	request := func(method, path, userID string) int {
		req := httptest.NewRequest(method, path, nil)
		req.Header.Set("X-Auth-User-ID", userID)
		response := httptest.NewRecorder()
		router.ServeHTTP(response, req)
		return response.Code
	}
	for range 10 {
		require.Equal(t, http.StatusNoContent, request(http.MethodGet, "/files/data/preview-upload-url?fileID=1&type=vid_preview", "1"))
		require.Equal(t, http.StatusNoContent, request(http.MethodGet, "/files/data/preview-upload-url?fileID=2&type=vid_preview&isMultiPart=true&count=2", "1"))
	}
	require.Equal(t, http.StatusTooManyRequests, request(http.MethodGet, "/files/data/preview-upload-url?fileID=3&type=vid_preview", "1"))
	require.Equal(t, http.StatusTooManyRequests, request(http.MethodPost, "/files/data/preview-upload-url", "1"))
	require.Equal(t, http.StatusNoContent, request(http.MethodGet, "/files/data/preview-upload-url?fileID=3&type=vid_preview", "2"))
	for range 10 {
		require.Equal(t, http.StatusNoContent, request(http.MethodPost, "/files/data/multipart-preview-upload-url", "1"))
	}
	require.Equal(t, http.StatusTooManyRequests, request(http.MethodPost, "/files/data/multipart-preview-upload-url", "1"))
	require.Equal(t, http.StatusNoContent, request(http.MethodPost, "/files/data/multipart-preview-upload-url", "2"))
	for range 20 {
		require.Equal(t, http.StatusNoContent, request(http.MethodPost, "/files/data/preview-upload-url", "3"))
	}
	require.Equal(t, http.StatusTooManyRequests, request(http.MethodPost, "/files/data/preview-upload-url", "3"))
	require.Equal(t, http.StatusNoContent, request(http.MethodPost, "/files/data/preview-upload-url", "2"))
}
