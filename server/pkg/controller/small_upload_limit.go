package controller

import (
	"strconv"
	"sync"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
	"github.com/patrickmn/go-cache"
	"golang.org/x/sync/singleflight"
)

const smallUploadLimit = 1000
const smallUploadWindow = 10 * time.Minute
const smallUploadEntitlementTTL = 30 * time.Second

type smallUploadLimiter struct {
	mu                sync.Mutex
	requests          *cache.Cache
	paidStatus        *cache.Cache
	paidStatusLookups singleflight.Group
}

func (l *smallUploadLimiter) allow(userID int64) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.requests == nil {
		l.requests = cache.New(smallUploadWindow, time.Minute)
		l.paidStatus = cache.New(smallUploadEntitlementTTL, time.Minute)
	}
	now := time.Now()
	key := strconv.FormatInt(userID, 10)
	var requests []time.Time
	if value, ok := l.requests.Get(key); ok {
		requests = value.([]time.Time)
	}
	cutoff := now.Add(-smallUploadWindow)
	for len(requests) > 0 && !requests[0].After(cutoff) {
		requests = requests[1:]
	}
	allowed := len(requests) < smallUploadLimit
	if !allowed {
		requests = requests[1:]
	}
	l.requests.Set(key, append(requests, now), cache.DefaultExpiration)
	return allowed
}

func (c *UsageController) CheckUploadURLRateLimit(userID int64, size *int64) error {
	if size != nil && *size < 2*1024 && !c.smallUploads.allow(userID) {
		key := strconv.FormatInt(userID, 10)
		isPaid, err, _ := c.smallUploads.paidStatusLookups.Do(key, func() (any, error) {
			if value, ok := c.smallUploads.paidStatus.Get(key); ok {
				return value, nil
			}
			value, err := c.BillingCtrl.BillingRepo.IsUserOnActivePaidPlan(userID)
			if err == nil {
				c.smallUploads.paidStatus.Set(key, value, cache.DefaultExpiration)
			}
			return value, err
		})
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		if !isPaid.(bool) {
			return ente.ErrSmallUploadLimitReached
		}
	}
	return nil
}
