package middleware

import (
	"fmt"
	"net/http"
	"strings"
	"sync/atomic"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller/discord"
	util "github.com/ente/museum/pkg/utils"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/network"

	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
	"github.com/ulule/limiter/v3"
)

type RateLimitMiddleware struct {
	count              int64 // Use int64 for atomic operations
	limit              int64
	reset              time.Duration
	ticker             *time.Ticker
	limit10ReqPerMin   *limiter.Limiter
	limit120ReqPerHour *limiter.Limiter
	limit200ReqPerMin  *limiter.Limiter
	limit250ReqPerMin  *limiter.Limiter
	limit300ReqPerMin  *limiter.Limiter
	limit500ReqPerMin  *limiter.Limiter
	limit700ReqPerSec  *limiter.Limiter
	discordCtrl        *discord.DiscordController
}

func NewRateLimitMiddleware(discordCtrl *discord.DiscordController, limit int64, reset time.Duration) *RateLimitMiddleware {
	rl := &RateLimitMiddleware{
		limit10ReqPerMin:   util.NewRateLimiter("10-M"),
		limit120ReqPerHour: util.NewRateLimiter("120-H"),
		limit200ReqPerMin:  util.NewRateLimiter("200-M"),
		limit250ReqPerMin:  util.NewRateLimiter("250-M"),
		limit300ReqPerMin:  util.NewRateLimiter("300-M"),
		limit500ReqPerMin:  util.NewRateLimiter("500-M"),
		limit700ReqPerSec:  util.NewRateLimiter("700-S"),
		discordCtrl:        discordCtrl,
		limit:              limit,
		reset:              reset,
		ticker:             time.NewTicker(reset),
	}
	go func() {
		for range rl.ticker.C {
			atomic.StoreInt64(&rl.count, 0) // Reset the count every reset interval
		}
	}()
	return rl
}

// Increment increments the counter in a thread-safe manner.
// Returns true if the increment was within the rate limit, false if the rate limit was exceeded.
func (r *RateLimitMiddleware) Increment() bool {
	// Atomically increment the count
	newCount := atomic.AddInt64(&r.count, 1)
	return newCount <= r.limit
}

// Stop the internal ticker, effectively stopping the rate limiter.
func (r *RateLimitMiddleware) Stop() {
	r.ticker.Stop()
}

// GlobalRateLimiter rate limits all requests to the server, regardless of the endpoint.
func (r *RateLimitMiddleware) GlobalRateLimiter() gin.HandlerFunc {
	return func(c *gin.Context) {
		if !r.Increment() {
			if r.count%100 == 0 {
				go r.discordCtrl.NotifyPotentialAbuse(fmt.Sprintf("Global ratelimit (%d) breached %d", r.limit, r.count))
			}
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{"error": "Rate limit breached, try later"})
			return
		}
		c.Next()
	}
}

// APIRateLimitMiddleware only rate limits sensitive public endpoints which have a higher risk
// of abuse by any bad actor.
func (r *RateLimitMiddleware) APIRateLimitMiddleware(urlSanitizer func(_ *gin.Context) string) gin.HandlerFunc {
	return func(c *gin.Context) {
		requestPath := urlSanitizer(c)

		if globalRateLimiter := r.getGlobalLimiter(requestPath, c.Request.Method); globalRateLimiter != nil {
			if r.isRateLimited(c, globalRateLimiter, globalRateLimitKey(requestPath), fmt.Sprintf("🌍 Global rate limit: %s", requestPath)) {
				return
			}
		}

		rateLimiter := r.getLimiter(requestPath, c.Request.Method)
		if rateLimiter != nil {
			key := r.getRateLimitKey(c, requestPath)
			if r.isRateLimited(c, rateLimiter, key, fmt.Sprintf("🌐 IP rate limit: %s", requestPath)) {
				return
			}
		}
		c.Next()
	}
}

// APIRateLimitForUserMiddleware only rate limits sensitive authenticated endpoints which have a higher risk
// of abuse by any bad actor.
func (r *RateLimitMiddleware) APIRateLimitForUserMiddleware(urlSanitizer func(_ *gin.Context) string) gin.HandlerFunc {
	return func(c *gin.Context) {
		requestPath := urlSanitizer(c)
		if globalRateLimiter := r.getGlobalLimiter(requestPath, c.Request.Method); globalRateLimiter != nil {
			if r.isRateLimited(c, globalRateLimiter, globalRateLimitKey(requestPath), fmt.Sprintf("🌍 Global rate limit: %s", requestPath)) {
				return
			}
		}

		rateLimiter := r.getLimiter(requestPath, c.Request.Method)
		if rateLimiter != nil {
			userID := auth.GetUserID(c.Request.Header)
			if userID == 0 {
				// do not apply limit, just log
				log.Error("userID must be present in request header for applying rate-limit")
				return
			}
			if r.isRateLimited(c, rateLimiter, fmt.Sprintf("%d-%s", userID, requestPath), fmt.Sprintf("👤 User rate limit: %s user=%d", requestPath, userID)) {
				return
			}
		}
		c.Next()
	}
}

func (r *RateLimitMiddleware) isRateLimited(c *gin.Context, rateLimiter *limiter.Limiter, key string, message string) bool {
	limitContext, err := rateLimiter.Get(c, key)
	if err != nil {
		log.Error("Failed to check rate limit", err)
		return false
	}
	if !limitContext.Reached {
		return false
	}
	go r.discordCtrl.NotifyPotentialAbuse(message)
	log.Error(fmt.Sprintf("Rate limit breached %s", key))
	c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{"error": "Rate limit breached, try later"})
	return true
}

// getGlobalLimiter, based on reqPath & reqMethod, returns a limiter that should
// be applied globally for requests matching the route. It returns nil if no
// global route-specific limit should be applied.
func (r *RateLimitMiddleware) getGlobalLimiter(reqPath string, reqMethod string) *limiter.Limiter {
	if isEventURLPath(reqPath) {
		return r.limit120ReqPerHour
	}
	if reqPath == "/paste/create" || reqPath == "/paste/guard" || reqPath == "/paste/consume" {
		return r.limit300ReqPerMin
	}
	return nil
}

func globalRateLimitKey(reqPath string) string {
	if isEventURLPath(reqPath) {
		return "/events"
	}
	return reqPath
}

func (r *RateLimitMiddleware) getRateLimitKey(c *gin.Context, reqPath string) string {
	if !isPublicCollectionUploadURLPath(reqPath) {
		return fmt.Sprintf("%s-%s", network.GetClientIP(c), reqPath)
	}
	value, ok := c.Get(auth.PublicAccessKey)
	if !ok {
		log.WithField("path", reqPath).Warn("public access context missing for collection scoped rate limit")
		return fmt.Sprintf("%s-%s", network.GetClientIP(c), reqPath)
	}
	accessContext, ok := value.(ente.PublicAccessContext)
	if !ok {
		log.WithField("path", reqPath).Warn("invalid public access context for collection scoped rate limit")
		return fmt.Sprintf("%s-%s", network.GetClientIP(c), reqPath)
	}
	return fmt.Sprintf("collection:%d-%s", accessContext.CollectionID, reqPath)
}

func isPublicCollectionUploadURLPath(reqPath string) bool {
	return reqPath == "/public-collection/upload-url" ||
		reqPath == "/public-collection/multipart-upload-url"
}

func isAuthenticatedUploadURLPath(reqPath string) bool {
	return reqPath == "/files/upload-urls" ||
		reqPath == "/files/upload-url" ||
		reqPath == "/files/multipart-upload-urls" ||
		reqPath == "/files/multipart-upload-url"
}

func isEventURLPath(reqPath string) bool {
	return reqPath == "/events" ||
		reqPath == "/events/user"
}

// getLimiter, based on reqPath & reqMethod, return instance of limiter.Limiter which needs to
// be applied for a request. It returns nil if the request is not rate limited
func (r *RateLimitMiddleware) getLimiter(reqPath string, reqMethod string) *limiter.Limiter {
	if strings.HasPrefix(reqPath, "/files/preview/") {
		return r.limit700ReqPerSec
	}
	if isAuthenticatedUploadURLPath(reqPath) {
		return r.limit500ReqPerMin
	}
	if isPublicCollectionUploadURLPath(reqPath) {
		return r.limit250ReqPerMin
	}
	if reqPath == "/users/public-key" {
		return r.limit200ReqPerMin
	}
	if reqPath == "/paste/guard" || reqPath == "/paste/consume" {
		return r.limit200ReqPerMin
	}
	if reqPath == "/custom-domain" {
		return r.limit500ReqPerMin
	}
	if reqPath == "/users/ott" ||
		reqPath == "/users/verify-email" ||
		reqPath == "/users/change-email" ||
		reqPath == "/paste/create" ||
		reqPath == "/discount/claim" ||
		reqPath == "/public-collection/verify-password" ||
		reqPath == "/file-link/verify-password" ||
		reqPath == "/family/accept-invite" ||
		reqPath == "/users/srp/attributes" ||
		(reqPath == "/cast/device-info" && reqMethod == "POST") ||
		(reqPath == "/cast/device-info/" && reqMethod == "POST") ||
		reqPath == "/users/srp/create-session" ||
		reqPath == "/users/srp/verify-session" ||
		reqPath == "/family/invite-info/:token" ||
		reqPath == "/family/add-member" ||
		strings.HasPrefix(reqPath, "/users/srp/") ||
		strings.HasPrefix(reqPath, "/users/two-factor/") {
		return r.limit10ReqPerMin
	}
	if reqPath == "/public-collection/anon-identity" {
		return r.limit10ReqPerMin
	}
	if (strings.HasPrefix(reqPath, "/public-collection/comments") ||
		strings.HasPrefix(reqPath, "/public-collection/reactions")) &&
		(reqMethod == http.MethodPost || reqMethod == http.MethodPut || reqMethod == http.MethodDelete) {
		return r.limit200ReqPerMin
	}
	return nil
}
