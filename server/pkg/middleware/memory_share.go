package middleware

import (
	"net/http"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/network"
	"github.com/gin-gonic/gin"
)

type MemoryShareMiddleware struct {
	Repo *repo.MemoryShareRepository
}

func (m *MemoryShareMiddleware) Authenticate(urlSanitizer func(_ *gin.Context) string) gin.HandlerFunc {
	return func(c *gin.Context) {
		_ = urlSanitizer
		accessToken := auth.GetAccessToken(c)
		if accessToken == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing accessToken", "context": "memory_share"})
			return
		}

		clientIP := network.GetClientIP(c)
		userAgent := c.GetHeader("User-Agent")

		share, err := m.Repo.GetByAccessToken(c, accessToken)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
			return
		}

		if share.IsDeleted {
			c.AbortWithStatusJSON(http.StatusGone, gin.H{"code": ente.LinkDisabled, "error": "memory share is deleted"})
			return
		}
		if ente.IsMemoryShareExpired(share.CreatedAt) {
			c.AbortWithStatusJSON(http.StatusGone, gin.H{"code": ente.LinkExpired, "error": "expired token"})
			return
		}

		accessCtx := ente.MemoryShareAccessContext{
			ID:          share.ID,
			ShareID:     share.ID,
			AccessToken: accessToken,
			IP:          clientIP,
			UserAgent:   userAgent,
		}
		c.Set(auth.MemoryShareAccessKey, accessCtx)

		c.Next()
	}
}
