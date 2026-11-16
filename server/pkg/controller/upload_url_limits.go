package controller

import (
	"context"
	"errors"
	"strconv"
	"sync"
	"time"

	"github.com/ente/museum/ente"
	"github.com/patrickmn/go-cache"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

const pendingUploadLimit = 1000
const pendingUploadWindow = time.Hour
const pendingUploadCheckEvery = 50
const uploadLimitCacheTTL = time.Minute
const smallUploadMaxSize = 10 * 1024
const smallUploadEntitlementTTL = 30 * time.Second
const smallUploadShortLimit = 1000
const smallUploadDailyLimit = 10000
const smallUploadShortWindow = 10 * time.Minute
const smallUploadDailyWindow = 24 * time.Hour

var uploadGuardRejections = promauto.NewCounterVec(prometheus.CounterOpts{
	Name: "museum_upload_guard_rejections_total",
	Help: "Upload grant admission rejections by policy.",
}, []string{"reason"})

type uploadLimitRepository interface {
	CountPending(context.Context, int64, time.Time, int) (int, error)
}

type smallUploadBucket struct {
	end   time.Time
	count int
}

type uploadLimitState struct {
	mu                 sync.Mutex
	remaining          int
	inFlight           int
	checkedAt          time.Time
	blockedUntil       time.Time
	buckets            []smallUploadBucket
	entitlementExpires time.Time
	paid               bool
}

func (s *uploadLimitState) smallRetryAt(now time.Time, count int) time.Time {
	cutoff := now.Add(-smallUploadDailyWindow)
	first := 0
	for first < len(s.buckets) && !s.buckets[first].end.After(cutoff) {
		first++
	}
	if first > 0 {
		s.buckets = s.buckets[:copy(s.buckets, s.buckets[first:])]
	}
	var retryAt time.Time
	for _, window := range []struct {
		duration time.Duration
		limit    int
	}{
		{smallUploadShortWindow, smallUploadShortLimit},
		{smallUploadDailyWindow, smallUploadDailyLimit},
	} {
		total := count
		cutoff := now.Add(-window.duration)
		for _, b := range s.buckets {
			if b.end.After(cutoff) {
				total += b.count
			}
		}
		for _, b := range s.buckets {
			if total <= window.limit {
				break
			}
			if b.end.After(cutoff) {
				total -= b.count
				if at := b.end.Add(window.duration); at.After(retryAt) {
					retryAt = at
				}
			}
		}
	}
	return retryAt
}

func (s *uploadLimitState) recordSmall(now time.Time, count int) {
	end := now.Truncate(time.Minute).Add(time.Minute)
	if n := len(s.buckets); n > 0 && s.buckets[n-1].end.Equal(end) {
		s.buckets[n-1].count += count
	} else {
		s.buckets = append(s.buckets, smallUploadBucket{end: end, count: count})
	}
}

type uploadURLLimiter struct {
	mu     sync.Mutex
	states *cache.Cache
}

func (l *uploadURLLimiter) state(userID int64) *uploadLimitState {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.states == nil {
		l.states = cache.New(25*time.Hour, time.Minute)
	}
	key := strconv.FormatInt(userID, 10)
	var state *uploadLimitState
	if value, ok := l.states.Get(key); ok {
		state = value.(*uploadLimitState)
	} else {
		state = &uploadLimitState{}
	}
	l.states.Set(key, state, cache.DefaultExpiration)
	return state
}

func (c *UsageController) ReserveUploadURLs(ctx context.Context, userID int64, size *int64, count int) (release func(), err error) {
	defer func() {
		var limited *ente.UploadRateLimitError
		if errors.As(err, &limited) {
			uploadGuardRejections.WithLabelValues(string(limited.Reason.Code)).Inc()
		}
	}()
	if count <= 0 || count > pendingUploadLimit {
		return nil, ente.ErrBadRequest
	}
	state := c.uploadLimits.state(userID)
	state.mu.Lock()
	defer state.mu.Unlock()
	now := time.Now()
	if now.Before(state.blockedUntil) {
		return nil, &ente.UploadRateLimitError{Reason: ente.ErrPendingUploadLimitReached, RetryAfter: state.blockedUntil.Sub(now)}
	}
	isSmall := size == nil || *size < smallUploadMaxSize
	recordSmall := false
	if isSmall {
		retryAt := state.smallRetryAt(now, count)
		recordSmall = retryAt.IsZero()
		if !retryAt.IsZero() {
			if !now.Before(state.entitlementExpires) {
				paid, queryErr := c.BillingCtrl.BillingRepo.IsUserOnActivePaidPlan(userID)
				if queryErr != nil {
					return nil, queryErr
				}
				state.paid = paid
				state.entitlementExpires = now.Add(smallUploadEntitlementTTL)
			}
			if !state.paid {
				return nil, &ente.UploadRateLimitError{Reason: ente.ErrSmallUploadLimitReached, RetryAfter: retryAt.Sub(now)}
			}
		}
	}
	if state.remaining < count || now.Sub(state.checkedAt) >= uploadLimitCacheTTL {
		pending, queryErr := c.UploadURLRepo.CountPending(ctx, userID, now.Add(-pendingUploadWindow), pendingUploadLimit)
		if queryErr != nil {
			return nil, queryErr
		}
		state.checkedAt = now
		state.remaining = min(pendingUploadCheckEvery, pendingUploadLimit-pending-state.inFlight)
		if pending+state.inFlight+count > pendingUploadLimit {
			state.blockedUntil = now.Add(uploadLimitCacheTTL)
			return nil, &ente.UploadRateLimitError{Reason: ente.ErrPendingUploadLimitReached, RetryAfter: uploadLimitCacheTTL}
		}
	}
	if recordSmall {
		state.recordSmall(now, count)
	}
	state.remaining -= count
	state.inFlight += count
	var once sync.Once
	return func() {
		once.Do(func() {
			state.mu.Lock()
			state.inFlight -= count
			state.mu.Unlock()
		})
	}, nil
}
