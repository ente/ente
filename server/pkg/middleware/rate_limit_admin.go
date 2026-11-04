package middleware

import (
	"fmt"
	"net/http"

	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
	"github.com/ulule/limiter/v3"
)

// AdminRateLimitMiddleware applies per-admin, per-route limits to the admin
// API. It must run after AdminAuthMiddleware, so the admin's user ID is set.
//
// The limits assume a person doing support, and cap how much a stolen admin
// token can read or change in an hour.
func (r *RateLimitMiddleware) AdminRateLimitMiddleware(urlSanitizer func(_ *gin.Context) string) gin.HandlerFunc {
	return func(c *gin.Context) {
		requestPath := urlSanitizer(c)
		userID := auth.GetUserID(c.Request.Header)
		if r.isRateLimited(c, r.adminLimiter(requestPath, c.Request.Method),
			fmt.Sprintf("%d-%s", userID, requestPath), requestPath, rateLimitScopeAdmin,
			fmt.Sprintf("🛡️ Admin rate limit: %s admin=%d", requestPath, userID)) {
			return
		}
		c.Next()
	}
}

// adminLimiter returns the limit for one admin route. Each admin has a
// separate budget per route.
func (r *RateLimitMiddleware) adminLimiter(reqPath string, reqMethod string) *limiter.Limiter {
	switch reqPath {
	case "/admin/users", "/admin/email-hash", "/admin/emails-from-hashes":
		// Bulk or reverse lookups of user data. Only self-hosted instances
		// serve these.
		return r.limit10ReqPerHour
	}
	if reqMethod == http.MethodGet || reqMethod == http.MethodHead {
		// Single-user lookups.
		return r.limit30ReqPerHour
	}
	return r.limit10ReqPerHour
}
