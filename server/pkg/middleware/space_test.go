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

func TestSpacePresignAllowsPhotoBatchesAfterProfileUploads(t *testing.T) {
	gin.SetMode(gin.TestMode)
	rateLimiter := NewRateLimitMiddleware(discord.NewDiscordController(nil, "test", "test"), 1000, time.Minute)
	t.Cleanup(rateLimiter.Stop)
	router := gin.New()
	router.POST("/spaces/:spaceID/uploads/presign", rateLimiter.APIRateLimitForUserMiddleware(func(c *gin.Context) string {
		return c.FullPath()
	}), func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})
	request := func() int {
		req := httptest.NewRequest(http.MethodPost, "/spaces/test-space/uploads/presign", nil)
		req.RemoteAddr = "192.0.2.1:1234"
		req.Header.Set("X-Auth-User-ID", "1")
		response := httptest.NewRecorder()
		router.ServeHTTP(response, req)
		return response.Code
	}
	for range 2 {
		require.Equal(t, http.StatusNoContent, request())
	}
	for range 10 {
		require.Equal(t, http.StatusNoContent, request())
	}
	for range 48 {
		require.Equal(t, http.StatusNoContent, request())
	}
	require.Equal(t, http.StatusTooManyRequests, request())
}
