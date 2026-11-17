package controller

import (
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/prometheus/client_golang/prometheus/testutil"
	"github.com/stretchr/testify/require"
)

type uploadActivityTestNotifier struct {
	messages chan string
}

func (n *uploadActivityTestNotifier) NotifyUploadActivity(message string) {
	n.messages <- message
}

func (n *uploadActivityTestNotifier) next(t *testing.T) string {
	t.Helper()
	select {
	case message := <-n.messages:
		return message
	case <-time.After(time.Second):
		t.Fatal("upload activity notification not received")
		return ""
	}
}

func (n *uploadActivityTestNotifier) expectNoMessage(t *testing.T) {
	t.Helper()
	select {
	case message := <-n.messages:
		t.Fatalf("unexpected upload activity notification: %s", message)
	case <-time.After(20 * time.Millisecond):
	}
}

func TestTinyUploadDailyBudgetBlocksSlowIssuance(t *testing.T) {
	c := newUploadLimitTestController(0)
	state := c.uploadLimits.state(1)
	now := time.Now()
	for hour := 5; hour > 0; hour-- {
		state.recordUpload(now.Add(-time.Duration(hour)*time.Hour), 400, uploadSizeTiny)
	}
	size := int64(32)
	_, err := c.ReserveUploadURLs(t.Context(), 1, &size, 1)
	require.ErrorIs(t, err, ente.ErrTinyUploadLimitReached)
	var limited *ente.UploadRateLimitError
	require.ErrorAs(t, err, &limited)
	require.WithinDuration(t, state.buckets[0].end.Add(smallUploadDailyWindow), time.Now().Add(limited.RetryAfter), time.Second)
	require.Zero(t, c.UploadURLRepo.(*pendingUploadTestRepository).calls.Load())
	tiny, unknown := state.tinyCounts(now)
	require.Equal(t, 2000, tiny)
	require.Zero(t, unknown)
}

func TestTinyUploadBudgetBoundariesAndUnknownSizes(t *testing.T) {
	c := newUploadLimitTestController(0)
	state := c.uploadLimits.state(1)
	now := time.Now()
	state.recordUpload(now.Add(-2*time.Hour), 1000, uploadSizeTiny)
	state.recordUpload(now.Add(-time.Hour), 1000, uploadSizeUnknown)
	for _, size := range []int64{1, 2047, 2048, 10239, 10240} {
		release, err := c.ReserveUploadURLs(t.Context(), 1, &size, 1)
		if size < 2048 {
			require.ErrorIs(t, err, ente.ErrTinyUploadLimitReached)
		} else {
			require.NoError(t, err)
			release()
		}
	}
	_, err := c.ReserveUploadURLs(t.Context(), 1, nil, 1)
	require.ErrorIs(t, err, ente.ErrTinyUploadLimitReached)
	tiny, unknown := state.tinyCounts(time.Now())
	require.Equal(t, 1000, tiny)
	require.Equal(t, 1000, unknown)
	state.buckets[0].end = now.Add(-25 * time.Hour)
	size := int64(32)
	release, err := c.ReserveUploadURLs(t.Context(), 1, &size, 1)
	require.NoError(t, err)
	release()
	tiny, unknown = state.tinyCounts(time.Now())
	require.Equal(t, 1, tiny)
	require.Equal(t, 1000, unknown)
}

func TestTinyUploadRetryAfterUsesBindingBudget(t *testing.T) {
	c := newUploadLimitTestController(0)
	state := c.uploadLimits.state(1)
	state.recordUpload(time.Now(), 2000, uploadSizeTiny)
	size := int64(32)
	_, err := c.ReserveUploadURLs(t.Context(), 1, &size, 1)
	require.ErrorIs(t, err, ente.ErrTinyUploadLimitReached)
	var limited *ente.UploadRateLimitError
	require.ErrorAs(t, err, &limited)
	require.Greater(t, limited.RetryAfter, 23*time.Hour)
}

func TestTinyUploadConcurrentDailyBoundary(t *testing.T) {
	c := newUploadLimitTestController(0)
	c.uploadLimits.state(1).recordUpload(time.Now().Add(-time.Hour), 1999, uploadSizeTiny)
	notifier := &uploadActivityTestNotifier{messages: make(chan string, 10)}
	c.UploadNotifier = notifier
	var accepted atomic.Int32
	var wg sync.WaitGroup
	size := int64(32)
	for range 100 {
		wg.Go(func() {
			release, err := c.ReserveUploadURLs(t.Context(), 1, &size, 1)
			if err == nil {
				accepted.Add(1)
				release()
			} else if !strings.Contains(err.Error(), string(ente.ErrTinyUploadLimitReached.Code)) {
				t.Errorf("unexpected error: %v", err)
			}
		})
	}
	wg.Wait()
	require.EqualValues(t, 1, accepted.Load())
	messages := []string{notifier.next(t), notifier.next(t)}
	require.Contains(t, strings.Join(messages, "\n"), "High tiny/unknown-size upload issuance")
	require.Contains(t, strings.Join(messages, "\n"), "reason=TINY_UPLOAD_LIMIT_REACHED")
	notifier.expectNoMessage(t)
}

func TestTinyUploadVolumeNoticeIncludesPaidUsersAndBatches(t *testing.T) {
	for _, paid := range []bool{false, true} {
		t.Run(map[bool]string{false: "free", true: "paid"}[paid], func(t *testing.T) {
			c := newUploadLimitTestController(0)
			state := c.uploadLimits.state(1)
			state.paid = paid
			state.recordUpload(time.Now().Add(-time.Hour), 980, uploadSizeTiny)
			notifier := &uploadActivityTestNotifier{messages: make(chan string, 10)}
			c.UploadNotifier = notifier
			release, err := c.ReserveUploadURLs(t.Context(), 1, nil, 50)
			require.NoError(t, err)
			release()
			message := notifier.next(t)
			require.Contains(t, message, "user=1")
			require.Contains(t, message, "admitted=1030 known_tiny=980 unknown=50")
			require.Contains(t, message, "window=24h threshold=1000")
			size := int64(32)
			for range 5 {
				release, err = c.ReserveUploadURLs(t.Context(), 1, &size, 1)
				require.NoError(t, err)
				release()
			}
			notifier.expectNoMessage(t)
			if paid {
				release, err = c.ReserveUploadURLs(t.Context(), 1, &size, 1000)
				require.NoError(t, err)
				release()
				release, err = c.ReserveUploadURLs(t.Context(), 1, &size, 500)
				require.NoError(t, err)
				release()
				tiny, unknown := state.tinyCounts(time.Now())
				require.Equal(t, 2485, tiny)
				require.Equal(t, 50, unknown)
				notifier.expectNoMessage(t)
			} else {
				state.lastNotified["tiny_upload_volume"] = time.Now().Add(-24 * time.Hour)
				release, err = c.ReserveUploadURLs(t.Context(), 1, &size, 1)
				require.NoError(t, err)
				release()
				require.Contains(t, notifier.next(t), "admitted=1036")
			}
			c.uploadLimits.state(2).recordUpload(time.Now().Add(-time.Hour), 999, uploadSizeTiny)
			release, err = c.ReserveUploadURLs(t.Context(), 2, &size, 1)
			require.NoError(t, err)
			release()
			require.Contains(t, notifier.next(t), "user=2")
		})
	}
}

func TestUploadGuardNoticesAreDeduplicatedWithoutExtraQueries(t *testing.T) {
	for _, reason := range []*ente.ApiError{ente.ErrPendingUploadLimitReached, ente.ErrTinyUploadLimitReached} {
		t.Run(string(reason.Code), func(t *testing.T) {
			c := newUploadLimitTestController(0)
			r := c.UploadURLRepo.(*pendingUploadTestRepository)
			state := c.uploadLimits.state(1)
			if reason == ente.ErrPendingUploadLimitReached {
				r.pending.Store(1000)
			} else {
				state.recordUpload(time.Now().Add(-time.Hour), 2000, uploadSizeTiny)
			}
			notifier := &uploadActivityTestNotifier{messages: make(chan string, 10)}
			c.UploadNotifier = notifier
			size := int64(32)
			_, err := c.ReserveUploadURLs(t.Context(), 1, &size, 1)
			require.ErrorIs(t, err, reason)
			require.Contains(t, notifier.next(t), "reason="+string(reason.Code))
			queries := r.calls.Load()
			for range 50 {
				_, err = c.ReserveUploadURLs(t.Context(), 1, nil, 50)
				require.ErrorIs(t, err, reason)
			}
			notifier.expectNoMessage(t)
			require.Equal(t, queries, r.calls.Load())
			state.lastNotified[string(reason.Code)] = time.Now().Add(-time.Hour)
			_, err = c.ReserveUploadURLs(t.Context(), 1, &size, 1)
			require.ErrorIs(t, err, reason)
			require.Contains(t, notifier.next(t), "reason="+string(reason.Code))
			require.Equal(t, queries, r.calls.Load())
		})
	}
}

func TestUploadGrantMetricsCountObjectsBySize(t *testing.T) {
	c := newUploadLimitTestController(0)
	for _, tc := range []struct {
		band uploadSizeBand
		size int64
	}{
		{uploadSizeTiny, 2047},
		{uploadSizeSmall, 2048},
		{uploadSizeLarge, 10240},
		{uploadSizeUnknown, 0},
	} {
		var size *int64
		if tc.band != uploadSizeUnknown {
			size = &tc.size
		}
		metric := uploadGrants.WithLabelValues(string(tc.band))
		before := testutil.ToFloat64(metric)
		release, err := c.ReserveUploadURLs(t.Context(), 1, size, 7)
		require.NoError(t, err)
		release()
		require.Equal(t, before+7, testutil.ToFloat64(metric))
		c.uploadLimits.state(1).blockedUntil = time.Now().Add(time.Minute)
		_, err = c.ReserveUploadURLs(t.Context(), 1, size, 7)
		require.ErrorIs(t, err, ente.ErrPendingUploadLimitReached)
		require.Equal(t, before+7, testutil.ToFloat64(metric))
		c.uploadLimits.state(1).blockedUntil = time.Time{}
	}
}
