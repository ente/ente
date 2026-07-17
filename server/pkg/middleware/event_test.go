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

func TestEventsUse120PerHourGlobalRateLimit(t *testing.T) {
	limit := util.NewRateLimiter("120-H")
	rateLimiter := &RateLimitMiddleware{limit120ReqPerHour: limit}

	require.Same(t, limit, rateLimiter.getGlobalLimiter("/events", http.MethodPost))
	require.Same(t, limit, rateLimiter.getGlobalLimiter("/events/user", http.MethodPost))
	require.Nil(t, rateLimiter.getLimiter("/events", http.MethodPost))
	require.Nil(t, rateLimiter.getLimiter("/events/user", http.MethodPost))
}

func TestSpaceRoutesUseRouteSpecificRateLimits(t *testing.T) {
	limit10ReqPerMin := util.NewRateLimiter("10-M")
	limit200ReqPerMin := util.NewRateLimiter("200-M")
	limit500ReqPerMin := util.NewRateLimiter("500-M")
	rateLimiter := &RateLimitMiddleware{
		limit10ReqPerMin:  limit10ReqPerMin,
		limit200ReqPerMin: limit200ReqPerMin,
		limit500ReqPerMin: limit500ReqPerMin,
	}

	require.Same(t, limit200ReqPerMin, rateLimiter.getLimiter("/space/public/by-slug/:spaceSlug", http.MethodGet))
	require.Same(t, limit200ReqPerMin, rateLimiter.getLimiter("/space/public/slug-availability/:spaceSlug", http.MethodGet))
	require.Same(t, limit10ReqPerMin, rateLimiter.getLimiter("/spaces/:spaceID/uploads/presign", http.MethodPost))
	require.Same(t, limit200ReqPerMin, rateLimiter.getLimiter("/spaces/:spaceID/profile", http.MethodGet))
	require.Same(t, limit500ReqPerMin, rateLimiter.getLimiter("/spaces/:spaceID/assets/redirect", http.MethodGet))
	require.Same(t, limit10ReqPerMin, rateLimiter.getLimiter("/spaces/:spaceID/conversations", http.MethodGet))
	require.Same(t, limit200ReqPerMin, rateLimiter.getLimiter("/spaces/:spaceID/posts", http.MethodGet))
	require.Same(t, limit200ReqPerMin, rateLimiter.getLimiter("/spaces/:spaceID/posts/:postID", http.MethodGet))
	require.Same(t, limit200ReqPerMin, rateLimiter.getLimiter("/spaces/:spaceID/versions", http.MethodGet))
	require.Same(t, limit200ReqPerMin, rateLimiter.getLimiter("/spaces/:spaceID/posts", http.MethodPost))
	require.Same(t, limit200ReqPerMin, rateLimiter.getLimiter("/spaces/:spaceID/messages/:messageID", http.MethodDelete))
	require.Same(t, limit10ReqPerMin, rateLimiter.getLimiter("/account/space", http.MethodPost))
	require.Same(t, limit10ReqPerMin, rateLimiter.getLimiter("/account/space/sessions", http.MethodPost))
	require.Same(t, limit10ReqPerMin, rateLimiter.getLimiter("/account/space/sessions/bootstrap", http.MethodPost))
	require.Same(t, limit10ReqPerMin, rateLimiter.getLimiter("/account/space/sessions/current", http.MethodDelete))
	require.Nil(t, rateLimiter.getLimiter("/account/space", http.MethodGet))
	require.Nil(t, rateLimiter.getLimiter("/spaces/:spaceID/feed", http.MethodGet))
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
