package middleware

import (
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/jwt"
	"github.com/ente/museum/pkg/controller/authsession"
	"github.com/ente/museum/pkg/utils/network"
	"github.com/sirupsen/logrus"

	"github.com/ente/museum/pkg/controller/user"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
	"github.com/patrickmn/go-cache"
	"github.com/spf13/viper"
)

type AuthMiddleware struct {
	UserAuthRepo   *repo.UserAuthRepository
	Cache          *cache.Cache
	UserController *user.UserController
}

func (m *AuthMiddleware) TokenAuthMiddleware(jwtClaimScope *jwt.ClaimScope) gin.HandlerFunc {
	return func(c *gin.Context) {
		token := auth.GetToken(c)
		if token == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing token"})
			return
		}
		app := auth.GetApp(c)
		var userID int64
		if jwtClaimScope == nil {
			tokenHash := auth.HashToken(token)
			var expired, cached bool
			var err error
			userID, expired, cached, err = authsession.Authenticate(m.UserAuthRepo, m.Cache, tokenHash[:], app)
			if err != nil && !errors.Is(err, sql.ErrNoRows) {
				logrus.Errorf("Failed to validate token: %s", err)
				c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"error": "failed to validate token"})
				return
			}
			if err != nil {
				c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
				return
			}
			if expired {
				logrus.Warningf("User token expired: %d", userID)
				c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "token expired"})
				return
			}
			if !cached {
				ip := network.GetClientIP(c)
				userAgent := c.Request.UserAgent()
				// skip updating last used for requests routed via CF worker
				if !network.IsCFWorkerIP(ip) {
					go func() {
						_ = m.UserAuthRepo.UpdateLastUsedAtByTokenHash(userID, tokenHash[:], ip, userAgent)
					}()
				}
			}
		} else {
			cacheKey := fmt.Sprintf("%s:%s:%s", app, token, *jwtClaimScope)
			cachedUserID, found := m.Cache.Get(cacheKey)
			if found {
				userID = cachedUserID.(int64)
			} else {
				claim, err := m.UserController.ValidateJWTToken(token, *jwtClaimScope)
				if err != nil {
					c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
					return
				}
				userID = claim.UserID
				m.Cache.Set(cacheKey, userID, cache.DefaultExpiration)
			}
		}
		c.Request.Header.Set("X-Auth-User-ID", strconv.FormatInt(userID, 10))
		c.Set(auth.AppContextKey, app)
		c.Next()
	}
}

func (m *AuthMiddleware) TokenOrJWTAuthMiddleware(jwtClaimScope jwt.ClaimScope) gin.HandlerFunc {
	userAuth := m.TokenAuthMiddleware(nil)
	jwtAuth := m.TokenAuthMiddleware(jwtClaimScope.Ptr())

	return func(c *gin.Context) {
		if strings.Contains(auth.GetToken(c), ".") {
			jwtAuth(c)
		} else {
			userAuth(c)
		}
	}
}

func RejectAuthApp() gin.HandlerFunc {
	return func(c *gin.Context) {
		app, ok := auth.GetAuthenticatedApp(c)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing authenticated app"})
			return
		}
		if app == ente.Auth {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "invalid app for endpoint"})
			return
		}
		c.Next()
	}
}

// NOTE: Should be added after TokenAuthMiddleware middleware
func (m *AuthMiddleware) AdminAuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := auth.GetUserID(c.Request.Header)
		admins := viper.GetIntSlice("internal.admins")
		for _, admin := range admins {
			if int64(admin) == userID {
				c.Next()
				return
			}
		}
		// The config allows alternatively specifying a singular admin ID to
		// workaround Viper issues in passing env vars for an int slice.
		admin := viper.GetInt("internal.admin")
		if len(admins) == 0 && admin != 0 {
			if int64(admin) == userID {
				c.Next()
				return
			}
		}
		// if no admins are set, then check if the user is first user in the system
		if len(admins) == 0 && admin == 0 {
			id, err := m.UserAuthRepo.GetMinUserID()
			if err == nil && id == userID {
				c.Next()
				return
			}
		}
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "insufficient permissions"})
	}
}
