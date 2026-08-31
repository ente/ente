package authsession

import (
	"database/sql"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/repo"
	"github.com/patrickmn/go-cache"
)

type cacheEntry struct {
	userID  int64
	revoked bool
}

func Authenticate(repo *repo.UserAuthRepository, authCache *cache.Cache, tokenHash []byte, app ente.App) (userID int64, expired, cached bool, err error) {
	cacheKey := tokenCacheKey(app, tokenHash)
	for {
		if value, ok := authCache.Get(cacheKey); ok {
			entry := value.(cacheEntry)
			if entry.revoked {
				return 0, false, false, sql.ErrNoRows
			}
			return entry.userID, false, true, nil
		}

		userID, expired, err = repo.GetUserIDWithTokenHash(tokenHash, app)
		if err != nil || expired {
			return
		}
		if err = authCache.Add(cacheKey, cacheEntry{userID: userID}, cache.DefaultExpiration); err == nil {
			return
		}
	}
}

func MarkRevoked(authCache *cache.Cache, tokens []repo.RevokedToken) {
	for _, token := range tokens {
		authCache.Set(tokenCacheKey(token.App, token.TokenHash), cacheEntry{revoked: true}, cache.DefaultExpiration)
	}
}

func tokenCacheKey(app ente.App, tokenHash []byte) string {
	return string(app) + ":" + string(tokenHash)
}
