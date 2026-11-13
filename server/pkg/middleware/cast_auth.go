package middleware

import (
	"net/http"

	castCtrl "github.com/ente/museum/pkg/controller/cast"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
)

type CastMiddleware struct {
	CastCtrl *castCtrl.Controller
}

func (m *CastMiddleware) CastAuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		token := auth.GetCastToken(c)
		if token == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "cast access token missing"})
			return
		}
		castCtx, err := m.CastCtrl.GetCollectionAndCasterIDForToken(c, token)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
			return
		}
		c.Set(auth.CastContext, *castCtx)
		c.Next()
	}
}
