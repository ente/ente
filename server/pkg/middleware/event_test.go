package middleware

import (
	"net/http"
	"testing"

	util "github.com/ente/museum/pkg/utils"
	"github.com/stretchr/testify/require"
)

func TestShouldSkipBodyLogForEvents(t *testing.T) {
	require.True(t, shouldSkipBodyLog(http.MethodPost, "/events"))
	require.True(t, shouldSkipBodyLog(http.MethodPost, "/events/user"))
	require.False(t, shouldSkipBodyLog(http.MethodGet, "/events"))
}

func TestEventsUseRouteRateLimit(t *testing.T) {
	limit := util.NewRateLimiter("10-M")
	rateLimiter := &RateLimitMiddleware{limit10ReqPerMin: limit}

	require.Same(t, limit, rateLimiter.getLimiter("/events", http.MethodPost))
	require.Same(t, limit, rateLimiter.getLimiter("/events/user", http.MethodPost))
}
