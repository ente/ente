package utils

import (
	"context"
	"time"

	"github.com/ulule/limiter/v3"
	"github.com/ulule/limiter/v3/drivers/store/common"
	"github.com/ulule/limiter/v3/drivers/store/memory"
)

// memoryLimiterStore keeps rate-limit keys as owned strings while reusing
// limiter/v3's in-memory cache. This is needed because the limiter/v3 memory
// driver stores keys derived from pooled byte buffers, which can mutate after
// insertion and break sync.Map's hash invariant.
type memoryLimiterStore struct {
	prefix string
	cache  *memory.CacheWrapper
}

func newMemoryLimiterStore() *memoryLimiterStore {
	return &memoryLimiterStore{
		prefix: limiter.DefaultPrefix,
		cache:  memory.NewCache(limiter.DefaultCleanUpInterval),
	}
}

func (store *memoryLimiterStore) Get(_ context.Context, key string, rate limiter.Rate) (limiter.Context, error) {
	now := time.Now()
	count, expiration := store.cache.Increment(store.cacheKey(key), 1, rate.Period)
	return common.GetContextFromState(now, rate, expiration, count), nil
}

func (store *memoryLimiterStore) Peek(_ context.Context, key string, rate limiter.Rate) (limiter.Context, error) {
	now := time.Now()
	count, expiration := store.cache.Get(store.cacheKey(key), rate.Period)
	return common.GetContextFromState(now, rate, expiration, count), nil
}

func (store *memoryLimiterStore) Reset(_ context.Context, key string, rate limiter.Rate) (limiter.Context, error) {
	now := time.Now()
	_, expiration := store.cache.Reset(store.cacheKey(key), rate.Period)
	return common.GetContextFromState(now, rate, expiration, 0), nil
}

func (store *memoryLimiterStore) cacheKey(key string) string {
	return store.prefix + ":" + key
}
