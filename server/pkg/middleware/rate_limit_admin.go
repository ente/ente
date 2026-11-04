package middleware

import (
	"fmt"
	"net/http"

	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
	"github.com/ulule/limiter/v3"
)

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

func (r *RateLimitMiddleware) adminLimiter(reqPath string, reqMethod string) *limiter.Limiter {
	switch reqPath {
	case "/admin/users", "/admin/email-hash", "/admin/emails-from-hashes":
		return r.limit10ReqPerHour
	}
	if reqMethod == http.MethodGet || reqMethod == http.MethodHead {
		return r.limit60ReqPerHour
	}
	return r.limit10ReqPerHour
}
