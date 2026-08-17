package middleware

import (
	"fmt"
	castCtrl "github.com/ente/museum/pkg/controller/cast"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
	"github.com/patrickmn/go-cache"
	"net/http"
)

type CastMiddleware struct {
	Cache    *cache.Cache
	CastCtrl *castCtrl.Controller
}

func (m *CastMiddleware) CastAuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		token := auth.GetCastToken(c)
		if token == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "cast access token missing"})
			return
		}
		app := auth.GetApp(c)
		cacheKey := fmt.Sprintf("%s:%s:%s", app, token, "cast")
		cachedCastCtx, found := m.Cache.Get(cacheKey)
		if !found {
			castCtx, err := m.CastCtrl.GetCollectionAndCasterIDForToken(c, token)
			if err != nil {
				c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
				return
			}
			c.Set(auth.CastContext, castCtx)
			m.Cache.Set(cacheKey, *castCtx, cache.DefaultExpiration)
			c.Set(auth.CastContext, *castCtx)
		} else {
			c.Set(auth.CastContext, cachedCastCtx)
			go func() {
				_, err := m.CastCtrl.GetCollectionAndCasterIDForToken(c, token)
				if err != nil {
					m.Cache.Delete(cacheKey)
				}
			}()
		}
		c.Next()
	}
}
