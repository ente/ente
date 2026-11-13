package public

import (
	"sync"
	"time"

	"github.com/ente/museum/pkg/utils/auth"
	"github.com/patrickmn/go-cache"
)

type LinkCache struct {
	cache    *cache.Cache
	lifetime time.Duration
	mu       sync.Mutex
}

type linkCacheEntry struct {
	value     any
	expiresAt int64
}

func NewLinkCache(defaultExpiration, cleanupInterval time.Duration) *LinkCache {
	return &LinkCache{cache: cache.New(defaultExpiration, cleanupInterval), lifetime: defaultExpiration}
}

func (c *LinkCache) Get(accessToken, key string) (any, bool) {
	if _, bypass := c.cache.Get(linkCacheBypassKey(accessToken)); bypass {
		return nil, false
	}
	value, found := c.cache.Get(key)
	if !found {
		return nil, false
	}
	entry := value.(linkCacheEntry)
	return entry.value, time.Now().UnixNano() < entry.expiresAt
}

func (c *LinkCache) Set(key string, value any, lookupStarted time.Time) {
	expiresAt := lookupStarted.Add(c.lifetime).UnixNano()
	if remaining := time.Duration(expiresAt - time.Now().UnixNano()); remaining > 0 {
		c.cache.Set(key, linkCacheEntry{value: value, expiresAt: expiresAt}, remaining)
	}
}

func (c *LinkCache) Invalidate(accessTokens ...string) {
	if c == nil {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	for _, accessToken := range accessTokens {
		c.cache.SetDefault(linkCacheBypassKey(accessToken), true)
	}
}

func linkCacheBypassKey(accessToken string) string {
	hash := auth.HashToken(accessToken)
	return "public-link-bypass:" + string(hash[:])
}
