package controller

import (
	"strconv"
	"sync"
	"testing"
	"time"
	"unsafe"

	"github.com/patrickmn/go-cache"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/testutil"
	"github.com/stretchr/testify/require"
)

func expireUploadMetricState(t *testing.T, limiter *uploadURLLimiter, userID int64) {
	t.Helper()
	key := strconv.FormatInt(userID, 10)
	value, ok := limiter.states.Get(key)
	require.True(t, ok)
	state := value.(*uploadLimitState)
	state.mu.Lock()
	state.cacheExpires.Store(time.Now().Add(-time.Hour).UnixNano())
	state.mu.Unlock()
	limiter.states.Set(key, state, time.Nanosecond)
	require.Eventually(t, func() bool {
		_, found := limiter.states.Get(key)
		return !found
	}, time.Second, time.Millisecond)
}

func TestUploadCacheMetricsTrackRetainedCapacityAndExpiry(t *testing.T) {
	entriesBefore := testutil.ToFloat64(uploadLimitCacheEntries)
	bytesBefore := testutil.ToFloat64(uploadLimitBucketBytes)
	limiter := &uploadURLLimiter{}
	state := limiter.state(1)
	require.Same(t, state, limiter.state(1))
	require.Equal(t, entriesBefore+1, testutil.ToFloat64(uploadLimitCacheEntries))
	require.Equal(t, bytesBefore, testutil.ToFloat64(uploadLimitBucketBytes))
	now := time.Now()
	for i := range 100 {
		state.recordUpload(now.Add(time.Duration(i)*time.Minute), 1, uploadSizeTiny)
	}
	retained := float64(cap(state.buckets)) * float64(unsafe.Sizeof(smallUploadBucket{}))
	require.Greater(t, retained, float64(100*unsafe.Sizeof(smallUploadBucket{})))
	require.Equal(t, bytesBefore+retained, testutil.ToFloat64(uploadLimitBucketBytes))
	state.smallRetryAt(now.Add(26*time.Hour), 1)
	require.Empty(t, state.buckets)
	require.Equal(t, bytesBefore+retained, testutil.ToFloat64(uploadLimitBucketBytes))
	expireUploadMetricState(t, limiter, 1)
	limiter.states.DeleteExpired()
	require.Equal(t, entriesBefore, testutil.ToFloat64(uploadLimitCacheEntries))
	require.Equal(t, bytesBefore, testutil.ToFloat64(uploadLimitBucketBytes))
	state.recordUpload(now.Add(27*time.Hour), 1, uploadSizeTiny)
	require.Equal(t, bytesBefore, testutil.ToFloat64(uploadLimitBucketBytes))
}

func TestUploadCacheMetricsReplaceExpiredEntryBeforeCleanup(t *testing.T) {
	entriesBefore := testutil.ToFloat64(uploadLimitCacheEntries)
	bytesBefore := testutil.ToFloat64(uploadLimitBucketBytes)
	limiter := &uploadURLLimiter{}
	old := limiter.state(1)
	old.recordUpload(time.Now(), 1, uploadSizeSmall)
	expireUploadMetricState(t, limiter, 1)
	current := limiter.state(1)
	require.NotSame(t, old, current)
	require.Equal(t, entriesBefore+1, testutil.ToFloat64(uploadLimitCacheEntries))
	require.Equal(t, bytesBefore, testutil.ToFloat64(uploadLimitBucketBytes))
	expireUploadMetricState(t, limiter, 1)
	limiter.states.DeleteExpired()
	require.Equal(t, entriesBefore, testutil.ToFloat64(uploadLimitCacheEntries))
}

func TestUploadCacheMetricsRefreshBeforeDelayedEviction(t *testing.T) {
	entriesBefore := testutil.ToFloat64(uploadLimitCacheEntries)
	bytesBefore := testutil.ToFloat64(uploadLimitBucketBytes)
	limiter := &uploadURLLimiter{}
	state := limiter.state(1)
	state.recordUpload(time.Now(), 1, uploadSizeSmall)
	expireUploadMetricState(t, limiter, 1)
	state.mu.Lock()
	finished := make(chan struct{})
	go func() {
		limiter.states.DeleteExpired()
		close(finished)
	}()
	require.Eventually(t, func() bool { return limiter.states.ItemCount() == 0 }, time.Second, time.Millisecond)
	state.cacheExpires.Store(time.Now().Add(uploadLimitStateTTL).UnixNano())
	limiter.states.Set("1", state, cache.DefaultExpiration)
	state.mu.Unlock()
	<-finished
	require.Equal(t, entriesBefore+1, testutil.ToFloat64(uploadLimitCacheEntries))
	require.Equal(t, bytesBefore+float64(unsafe.Sizeof(smallUploadBucket{})), testutil.ToFloat64(uploadLimitBucketBytes))
	expireUploadMetricState(t, limiter, 1)
	limiter.states.DeleteExpired()
	require.Equal(t, entriesBefore, testutil.ToFloat64(uploadLimitCacheEntries))
	require.Equal(t, bytesBefore, testutil.ToFloat64(uploadLimitBucketBytes))
}

func TestUploadCacheMetricsConcurrentRefreshAndRecord(t *testing.T) {
	entriesBefore := testutil.ToFloat64(uploadLimitCacheEntries)
	bytesBefore := testutil.ToFloat64(uploadLimitBucketBytes)
	limiter := &uploadURLLimiter{}
	now := time.Now().Truncate(time.Minute)
	var wg sync.WaitGroup
	for userID := range int64(10) {
		for range 10 {
			wg.Go(func() {
				state := limiter.state(userID)
				state.mu.Lock()
				defer state.mu.Unlock()
				state.recordUpload(now, 1, uploadSizeUnknown)
			})
		}
	}
	wg.Wait()
	require.Equal(t, entriesBefore+10, testutil.ToFloat64(uploadLimitCacheEntries))
	require.Equal(t, bytesBefore+10*float64(unsafe.Sizeof(smallUploadBucket{})), testutil.ToFloat64(uploadLimitBucketBytes))
	for userID := range int64(10) {
		expireUploadMetricState(t, limiter, userID)
	}
	limiter.states.DeleteExpired()
	require.Equal(t, entriesBefore, testutil.ToFloat64(uploadLimitCacheEntries))
	require.Equal(t, bytesBefore, testutil.ToFloat64(uploadLimitBucketBytes))
	registry := prometheus.NewPedanticRegistry()
	registry.MustRegister(uploadLimitCacheEntries, uploadLimitBucketBytes)
	families, err := registry.Gather()
	require.NoError(t, err)
	require.Len(t, families, 2)
	for _, family := range families {
		require.Len(t, family.Metric, 1)
		require.Empty(t, family.Metric[0].Label)
	}
}

func TestUploadCacheMetricRefreshDoesNotWaitForAdmission(t *testing.T) {
	limiter := &uploadURLLimiter{}
	state := limiter.state(1)
	state.mu.Lock()
	refreshed := make(chan *uploadLimitState, 1)
	go func() { refreshed <- limiter.state(1) }()
	select {
	case actual := <-refreshed:
		state.mu.Unlock()
		require.Same(t, state, actual)
	case <-time.After(time.Second):
		state.mu.Unlock()
		t.Fatal("cache refresh waited for an in-progress admission")
	}
	expireUploadMetricState(t, limiter, 1)
	limiter.states.DeleteExpired()
}
