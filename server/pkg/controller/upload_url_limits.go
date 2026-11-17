package controller

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"sync"
	"sync/atomic"
	"time"
	"unsafe"

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
const tinyUploadMaxSize = 2 * 1024
const tinyUploadDailyLimit = 2000
const tinyUploadNotifyThreshold = 1000
const uploadGuardNotifyInterval = time.Hour
const smallUploadEntitlementTTL = 30 * time.Second
const smallUploadShortLimit = 1000
const smallUploadDailyLimit = 10000
const smallUploadShortWindow = 10 * time.Minute
const smallUploadDailyWindow = 24 * time.Hour
const uploadLimitStateTTL = 25 * time.Hour

var uploadGuardRejections = promauto.NewCounterVec(prometheus.CounterOpts{
	Name: "museum_upload_guard_rejections_total",
	Help: "Upload grant admission rejections by policy.",
}, []string{"reason"})

var uploadGrants = promauto.NewCounterVec(prometheus.CounterOpts{
	Name: "museum_upload_grants_total",
	Help: "Object grants admitted, partitioned by declared content size.",
}, []string{"size_band"})

var uploadLimitCacheEntries = promauto.NewGauge(prometheus.GaugeOpts{
	Name: "museum_upload_limit_cache_entries",
	Help: "Upload limiter states retained in the process cache, including expired states awaiting cleanup.",
})

var uploadLimitBucketBytes = promauto.NewGauge(prometheus.GaugeOpts{
	Name: "museum_upload_limit_bucket_capacity_bytes",
	Help: "Estimated bytes in cached upload limiter bucket backing arrays; excludes state, map and allocator overhead.",
})

type uploadActivityNotifier interface {
	NotifyUploadActivity(string)
}

type uploadSizeBand string

const (
	uploadSizeTiny    uploadSizeBand = "lt_2_kib"
	uploadSizeSmall   uploadSizeBand = "2_to_10_kib"
	uploadSizeLarge   uploadSizeBand = "ge_10_kib"
	uploadSizeUnknown uploadSizeBand = "unknown"
)

func uploadBand(size *int64) uploadSizeBand {
	switch {
	case size == nil:
		return uploadSizeUnknown
	case *size < tinyUploadMaxSize:
		return uploadSizeTiny
	case *size < smallUploadMaxSize:
		return uploadSizeSmall
	default:
		return uploadSizeLarge
	}
}

type uploadLimitRepository interface {
	CountPending(context.Context, int64, time.Time, int) (int, error)
}

type smallUploadBucket struct {
	end     time.Time
	count   int
	tiny    int
	unknown int
}

type uploadLimitState struct {
	mu                 sync.Mutex
	cached             bool
	cacheExpires       atomic.Int64
	remaining          int
	inFlight           int
	pendingCount       int
	checkedAt          time.Time
	blockedUntil       time.Time
	buckets            []smallUploadBucket
	entitlementExpires time.Time
	paid               bool
	lastNotified       map[string]time.Time
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
	shortRetry := s.budgetRetryAt(now, count, smallUploadShortWindow, smallUploadShortLimit, false)
	dailyRetry := s.budgetRetryAt(now, count, smallUploadDailyWindow, smallUploadDailyLimit, false)
	if dailyRetry.After(shortRetry) {
		return dailyRetry
	}
	return shortRetry
}

func (s *uploadLimitState) budgetRetryAt(now time.Time, count int, window time.Duration, limit int, tiny bool) time.Time {
	cutoff := now.Add(-window)
	total := count
	bucketCount := func(b smallUploadBucket) int {
		if tiny {
			return b.tiny + b.unknown
		}
		return b.count
	}
	for _, b := range s.buckets {
		if b.end.After(cutoff) {
			total += bucketCount(b)
		}
	}
	if total <= limit {
		return time.Time{}
	}
	for _, b := range s.buckets {
		if b.end.After(cutoff) {
			total -= bucketCount(b)
			if total <= limit {
				return b.end.Add(window)
			}
		}
	}
	return time.Time{}
}

func (s *uploadLimitState) tinyCounts(now time.Time) (tiny, unknown int) {
	cutoff := now.Add(-smallUploadDailyWindow)
	for _, b := range s.buckets {
		if b.end.After(cutoff) {
			tiny += b.tiny
			unknown += b.unknown
		}
	}
	return
}

func (s *uploadLimitState) recordSmall(now time.Time, count int) {
	s.recordUpload(now, count, uploadSizeSmall)
}

func (s *uploadLimitState) recordUpload(now time.Time, count int, band uploadSizeBand) {
	end := now.Truncate(time.Minute).Add(time.Minute)
	if n := len(s.buckets); n == 0 || !s.buckets[n-1].end.Equal(end) {
		previousCapacity := cap(s.buckets)
		s.buckets = append(s.buckets, smallUploadBucket{end: end})
		if s.cached {
			uploadLimitBucketBytes.Add(float64(cap(s.buckets)-previousCapacity) * float64(unsafe.Sizeof(smallUploadBucket{})))
		}
	}
	bucket := &s.buckets[len(s.buckets)-1]
	bucket.count += count
	if band == uploadSizeTiny {
		bucket.tiny += count
	} else if band == uploadSizeUnknown {
		bucket.unknown += count
	}
}

func (s *uploadLimitState) shouldNotify(reason string, now time.Time, interval time.Duration) bool {
	if last, ok := s.lastNotified[reason]; ok && now.Sub(last) < interval {
		return false
	}
	if s.lastNotified == nil {
		s.lastNotified = make(map[string]time.Time)
	}
	s.lastNotified[reason] = now
	return true
}

type uploadURLLimiter struct {
	mu     sync.Mutex
	states *cache.Cache
}

func (l *uploadURLLimiter) state(userID int64) *uploadLimitState {
	l.mu.Lock()
	if l.states == nil {
		l.states = cache.New(uploadLimitStateTTL, time.Minute)
		l.states.OnEvicted(func(_ string, value interface{}) {
			state := value.(*uploadLimitState)
			state.mu.Lock()
			defer state.mu.Unlock()
			expires := state.cacheExpires.Load()
			if expires != 0 && time.Now().UnixNano() >= expires && state.cacheExpires.CompareAndSwap(expires, 0) && state.cached {
				state.cached = false
				uploadLimitCacheEntries.Dec()
				uploadLimitBucketBytes.Sub(float64(cap(state.buckets)) * float64(unsafe.Sizeof(smallUploadBucket{})))
			}
		})
	}
	key := strconv.FormatInt(userID, 10)
	var state *uploadLimitState
	if value, ok := l.states.Get(key); ok {
		state = value.(*uploadLimitState)
	} else {
		l.states.Delete(key)
		state = &uploadLimitState{}
	}
	previousExpiry := state.cacheExpires.Swap(time.Now().Add(uploadLimitStateTTL).UnixNano())
	l.states.Set(key, state, cache.DefaultExpiration)
	l.mu.Unlock()
	if previousExpiry == 0 {
		state.mu.Lock()
		if !state.cached && state.cacheExpires.Load() != 0 {
			state.cached = true
			uploadLimitCacheEntries.Inc()
			uploadLimitBucketBytes.Add(float64(cap(state.buckets)) * float64(unsafe.Sizeof(smallUploadBucket{})))
		}
		state.mu.Unlock()
	}
	return state
}

func (c *UsageController) ReserveUploadURLs(ctx context.Context, userID int64, size *int64, count int) (release func(), err error) {
	var notice string
	defer func() {
		if notice != "" {
			go c.UploadNotifier.NotifyUploadActivity(notice)
		}
		var limited *ente.UploadRateLimitError
		if errors.As(err, &limited) {
			uploadGuardRejections.WithLabelValues(string(limited.Reason.Code)).Inc()
		}
	}()
	if count <= 0 || count > pendingUploadLimit {
		return nil, ente.ErrBadRequest
	}
	// Public-link uploads intentionally share the owner's account limits.
	state := c.uploadLimits.state(userID)
	state.mu.Lock()
	defer state.mu.Unlock()
	now := time.Now()
	band := uploadBand(size)
	notifyPending := func() {
		if c.UploadNotifier != nil && state.shouldNotify(string(ente.ErrPendingUploadLimitReached.Code), now, uploadGuardNotifyInterval) {
			notice = fmt.Sprintf("Upload guard: reason=%s user=%d size_band=%s pending=%d in_flight=%d requested=%d limit=%d window=1h", ente.ErrPendingUploadLimitReached.Code, userID, band, state.pendingCount, state.inFlight, count, pendingUploadLimit)
		}
	}
	if now.Before(state.blockedUntil) {
		notifyPending()
		return nil, &ente.UploadRateLimitError{Reason: ente.ErrPendingUploadLimitReached, RetryAfter: state.blockedUntil.Sub(now)}
	}
	isSmall := band != uploadSizeLarge
	isTiny := band == uploadSizeTiny || band == uploadSizeUnknown
	if isSmall {
		retryAt := state.smallRetryAt(now, count)
		reason := ente.ErrSmallUploadLimitReached
		if isTiny {
			tinyRetry := state.budgetRetryAt(now, count, smallUploadDailyWindow, tinyUploadDailyLimit, true)
			if !tinyRetry.IsZero() && !tinyRetry.Before(retryAt) {
				retryAt, reason = tinyRetry, ente.ErrTinyUploadLimitReached
			}
		}
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
				if reason == ente.ErrTinyUploadLimitReached && c.UploadNotifier != nil && state.shouldNotify(string(reason.Code), now, uploadGuardNotifyInterval) {
					tiny, unknown := state.tinyCounts(now)
					notice = fmt.Sprintf("Upload guard: reason=%s user=%d size_band=lt_2_kib_or_unknown admitted=%d known_tiny=%d unknown=%d requested=%d limit=%d window=24h", reason.Code, userID, tiny+unknown, tiny, unknown, count, tinyUploadDailyLimit)
				}
				return nil, &ente.UploadRateLimitError{Reason: reason, RetryAfter: retryAt.Sub(now)}
			}
		}
	}
	if state.remaining < count || now.Sub(state.checkedAt) >= uploadLimitCacheTTL {
		pending, queryErr := c.UploadURLRepo.CountPending(ctx, userID, now.Add(-pendingUploadWindow), pendingUploadLimit)
		if queryErr != nil {
			return nil, queryErr
		}
		state.pendingCount = pending
		state.checkedAt = now
		state.remaining = min(pendingUploadCheckEvery, pendingUploadLimit-pending-state.inFlight)
		if pending+state.inFlight+count > pendingUploadLimit {
			state.blockedUntil = now.Add(uploadLimitCacheTTL)
			notifyPending()
			return nil, &ente.UploadRateLimitError{Reason: ente.ErrPendingUploadLimitReached, RetryAfter: uploadLimitCacheTTL}
		}
	}
	if isSmall {
		state.recordUpload(now, count, band)
	}
	if isTiny && c.UploadNotifier != nil {
		tiny, unknown := state.tinyCounts(now)
		if tiny+unknown >= tinyUploadNotifyThreshold && state.shouldNotify("tiny_upload_volume", now, smallUploadDailyWindow) {
			notice = fmt.Sprintf("High tiny/unknown-size upload issuance: user=%d size_band=lt_2_kib_or_unknown admitted=%d known_tiny=%d unknown=%d window=24h threshold=%d", userID, tiny+unknown, tiny, unknown, tinyUploadNotifyThreshold)
		}
	}
	uploadGrants.WithLabelValues(string(band)).Add(float64(count))
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
