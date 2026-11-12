package middleware

import (
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"github.com/ente/museum/pkg/controller/discord"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func newAdminRateLimitTestRouter(rl *RateLimitMiddleware) *gin.Engine {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	admin := router.Group("/admin")
	admin.Use(func(c *gin.Context) {
		c.Request.Header.Set("X-Auth-User-ID", c.GetHeader("Test-Admin"))
	}, rl.AdminRateLimitMiddleware(func(c *gin.Context) string { return c.FullPath() }))
	ok := func(c *gin.Context) { c.Status(http.StatusNoContent) }
	admin.GET("/user", ok)
	admin.GET("/users", ok)
	admin.GET("/email-hash", ok)
	admin.POST("/emails-from-hashes", ok)
	admin.POST("/user/add-ott", ok)
	admin.DELETE("/user/delete", ok)
	admin.POST("/user/bonus", ok)
	admin.PUT("/user/subscription", ok)
	return router
}

func adminRateLimitTestRequest(router *gin.Engine, adminID int, method, path string) int {
	req := httptest.NewRequest(method, path, nil)
	req.Header.Set("Test-Admin", strconv.Itoa(adminID))
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	return w.Code
}

func TestAdminRateLimits(t *testing.T) {
	rl := NewRateLimitMiddleware(discord.NewDiscordController(nil, "test", "test"), 1_000_000, 1_000_000, time.Hour)
	t.Cleanup(rl.Stop)
	router := newAdminRateLimitTestRouter(rl)

	tests := []struct {
		method, path string
		limit        int
	}{
		{http.MethodGet, "/admin/user", 60},
		{http.MethodGet, "/admin/users", 10},
		{http.MethodGet, "/admin/email-hash", 10},
		{http.MethodPost, "/admin/emails-from-hashes", 10},
		{http.MethodPost, "/admin/user/add-ott", 10},
		{http.MethodDelete, "/admin/user/delete", 10},
		{http.MethodPost, "/admin/user/bonus", 10},
	}
	for _, tt := range tests {
		t.Run(tt.method+" "+tt.path, func(t *testing.T) {
			for i := 0; i < tt.limit; i++ {
				require.Equal(t, http.StatusNoContent, adminRateLimitTestRequest(router, 1, tt.method, tt.path), "request %d", i+1)
			}
			require.Equal(t, http.StatusTooManyRequests, adminRateLimitTestRequest(router, 1, tt.method, tt.path))
			require.Equal(t, http.StatusNoContent, adminRateLimitTestRequest(router, 2, tt.method, tt.path))
		})
	}
	require.Equal(t, http.StatusNoContent, adminRateLimitTestRequest(router, 1, http.MethodPut, "/admin/user/subscription"))
}
