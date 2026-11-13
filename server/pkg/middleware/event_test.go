package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/ente/museum/pkg/controller/discord"
	util "github.com/ente/museum/pkg/utils"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestShouldSkipBodyLogForEvents(t *testing.T) {
	require.True(t, shouldSkipBodyLog(http.MethodPost, "/events"))
	require.True(t, shouldSkipBodyLog(http.MethodPost, "/events/user"))
	require.False(t, shouldSkipBodyLog(http.MethodGet, "/events"))
}

func TestShouldSkipBodyLogForSpaceKeyRoutes(t *testing.T) {
	require.True(t, shouldSkipBodyLog(http.MethodPost, "/account/space"))
	require.True(t, shouldSkipBodyLog(http.MethodPost, "/account/space/sessions"))
	require.True(t, shouldSkipBodyLog(http.MethodPost, "/user-entity/key"))
	require.True(t, shouldSkipBodyLog(http.MethodPost, "/user-entity/key/ensure"))
	require.True(t, shouldSkipBodyLog(http.MethodPost, "/spaces/space-id/posts"))

	require.False(t, shouldSkipBodyLog(http.MethodGet, "/account/space"))
	require.False(t, shouldSkipBodyLog(http.MethodGet, "/user-entity/key"))
}

func TestAccountRecoveryTokensAreNotLogged(t *testing.T) {
	require.True(t, shouldSkipBodyLog(http.MethodPost, "/users/recover-account/validate"))
	require.True(t, shouldSkipBodyLog(http.MethodPost, "/users/recover-account"))
	require.False(t, shouldSkipBodyLog(http.MethodGet, "/users/recover-account"))
}

func TestEventsShareGlobalRateLimitAcrossPublicAndAuthenticatedRoutes(t *testing.T) {
	gin.SetMode(gin.TestMode)
	rateLimiter := &RateLimitMiddleware{
		limit120ReqPerHour: util.NewRateLimiter("1-H"),
		discordCtrl:        discord.NewDiscordController(nil, "test", "test"),
	}
	router := gin.New()
	router.POST("/events", rateLimiter.APIRateLimitMiddleware(eventTestURLSanitizer), func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})
	router.POST("/events/user", rateLimiter.APIRateLimitForUserMiddleware(eventTestURLSanitizer), func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})

	require.Equal(t, http.StatusNoContent, performEventRequest(router, "/events", "198.51.100.1:1000", "1").Code)
	require.Equal(t, http.StatusTooManyRequests, performEventRequest(router, "/events/user", "198.51.100.2:1000", "2").Code)
}

func eventTestURLSanitizer(c *gin.Context) string {
	return c.Request.URL.Path
}

func performEventRequest(router *gin.Engine, path string, remoteAddr string, userID string) *httptest.ResponseRecorder {
	recorder := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, path, nil)
	req.RemoteAddr = remoteAddr
	req.Header.Set("X-Auth-User-ID", userID)
	router.ServeHTTP(recorder, req)
	return recorder
}
