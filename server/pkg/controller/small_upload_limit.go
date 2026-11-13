package controller

import (
	"strconv"
	"sync"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
	"github.com/patrickmn/go-cache"
)

const smallUploadLimit = 1000
const smallUploadWindow = 10 * time.Minute

type smallUploadLimiter struct {
	mu       sync.Mutex
	requests *cache.Cache
}

func (l *smallUploadLimiter) allow(userID int64) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.requests == nil {
		l.requests = cache.New(smallUploadWindow, time.Minute)
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
	if len(requests) >= smallUploadLimit {
		return false
	}
	l.requests.Set(key, append(requests, now), cache.DefaultExpiration)
	return true
}

func (c *UsageController) CheckUploadURLRateLimit(userID int64, size *int64) error {
	if size != nil && *size < 2*1024 && !c.smallUploads.allow(userID) {
		isPaid, err := c.BillingCtrl.BillingRepo.IsUserOnPaidPlan(userID)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		if !isPaid {
			return ente.ErrSmallUploadLimitReached
		}
	}
	return nil
}
