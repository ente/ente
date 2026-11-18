package controller

import (
	"context"
	"errors"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/stretchr/testify/require"
)

type pendingUploadTestRepository struct {
	pending atomic.Int64
	calls   atomic.Int64
	err     error
}

func (r *pendingUploadTestRepository) CountPending(_ context.Context, _ int64, _ time.Time, limit int) (int, error) {
	r.calls.Add(1)
	return min(int(r.pending.Load()), limit), r.err
}

func newUploadLimitTestController(pending int64) *UsageController {
	r := &pendingUploadTestRepository{}
	r.pending.Store(pending)
	c := &UsageController{UploadURLRepo: r}
	c.uploadLimits.state(1).entitlementExpires = time.Now().Add(time.Hour)
	return c
}

func isSmallUploadError(err error) bool { return errors.Is(err, ente.ErrSmallUploadLimitReached) }

func TestPendingUploadCheckCadence(t *testing.T) {
	c := newUploadLimitTestController(0)
	r := c.UploadURLRepo.(*pendingUploadTestRepository)
	size := int64(10240)
	for range 50 {
		release, err := c.ReserveUploadURLs(t.Context(), 1, &size, 1)
		require.NoError(t, err)
		release()
		release()
	}
	require.EqualValues(t, 1, r.calls.Load())
	release, err := c.ReserveUploadURLs(t.Context(), 1, &size, 1)
	require.NoError(t, err)
	release()
	require.EqualValues(t, 2, r.calls.Load())
	c.uploadLimits.state(1).checkedAt = time.Now().Add(-time.Minute)
	release, err = c.ReserveUploadURLs(t.Context(), 1, &size, 1)
	require.NoError(t, err)
	release()
	require.EqualValues(t, 3, r.calls.Load())
	require.Zero(t, c.uploadLimits.state(1).inFlight)
}

func TestCanceledUploadRequestDoesNotReserveURLs(t *testing.T) {
	c := newUploadLimitTestController(0)
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	size := int64(10240)
	_, err := c.ReserveUploadURLs(ctx, 1, &size, 1)
	require.ErrorIs(t, err, context.Canceled)
	require.Zero(t, c.UploadURLRepo.(*pendingUploadTestRepository).calls.Load())
	require.Zero(t, c.uploadLimits.state(1).inFlight)
}

func TestPendingUploadBatchAndCooldown(t *testing.T) {
	c := newUploadLimitTestController(970)
	r := c.UploadURLRepo.(*pendingUploadTestRepository)
	_, err := c.ReserveUploadURLs(t.Context(), 1, nil, 50)
	require.ErrorIs(t, err, ente.ErrPendingUploadLimitReached)
	require.Empty(t, c.uploadLimits.state(1).buckets)
	r.pending.Store(0)
	for range 100 {
		_, err = c.ReserveUploadURLs(t.Context(), 1, nil, 1)
		require.ErrorIs(t, err, ente.ErrPendingUploadLimitReached)
	}
	require.EqualValues(t, 1, r.calls.Load())
	state := c.uploadLimits.state(1)
	state.blockedUntil = time.Now().Add(-time.Second)
	state.checkedAt = time.Now().Add(-time.Minute)
	release, err := c.ReserveUploadURLs(t.Context(), 1, nil, 50)
	require.NoError(t, err)
	release()
	require.Equal(t, 50, state.buckets[0].count)
	require.EqualValues(t, 2, r.calls.Load())
	release, err = c.ReserveUploadURLs(t.Context(), 1, nil, 50)
	require.NoError(t, err)
	release()
	require.EqualValues(t, 3, r.calls.Load())
}

func TestPendingUploadsIncludeInflightReservations(t *testing.T) {
	c := newUploadLimitTestController(0)
	size := int64(1 << 20)
	releases := make(chan func(), 1200)
	var wg sync.WaitGroup
	for range 1200 {
		wg.Go(func() {
			release, err := c.ReserveUploadURLs(t.Context(), 1, &size, 1)
			if err == nil {
				releases <- release
			} else if !errors.Is(err, ente.ErrPendingUploadLimitReached) {
				t.Errorf("unexpected error: %v", err)
			}
		})
	}
	wg.Wait()
	close(releases)
	require.Len(t, releases, 1000)
	for release := range releases {
		release()
	}
	require.Zero(t, c.uploadLimits.state(1).inFlight)
}

func TestPendingGuardAppliesToPaidAndLargeUploads(t *testing.T) {
	c := newUploadLimitTestController(1000)
	c.uploadLimits.state(1).paid = true
	for _, size := range []int64{32, 10 << 20} {
		_, err := c.ReserveUploadURLs(t.Context(), 1, &size, 1)
		require.ErrorIs(t, err, ente.ErrPendingUploadLimitReached)
	}
	require.EqualValues(t, 1, c.UploadURLRepo.(*pendingUploadTestRepository).calls.Load())
}

func TestUploadAdmissionRejectsInvalidCountsAndFailsClosed(t *testing.T) {
	c := newUploadLimitTestController(0)
	r := c.UploadURLRepo.(*pendingUploadTestRepository)
	for _, count := range []int{0, -1, 1001} {
		_, err := c.ReserveUploadURLs(t.Context(), 1, nil, count)
		require.ErrorIs(t, err, ente.ErrBadRequest)
	}
	require.Zero(t, r.calls.Load())
	r.err = errors.New("unavailable")
	_, err := c.ReserveUploadURLs(t.Context(), 1, nil, 1)
	require.ErrorIs(t, err, r.err)
	require.Empty(t, c.uploadLimits.state(1).buckets)
	r.err = nil
	release, err := c.ReserveUploadURLs(t.Context(), 1, nil, 1)
	require.NoError(t, err)
	release()
}

func TestSmallUploadRejectionsDoNotQueryPendingOrExtendBudget(t *testing.T) {
	c := newUploadLimitTestController(0)
	state := c.uploadLimits.state(1)
	state.recordSmall(time.Now(), 1000)
	size := int64(32)
	before := state.buckets[0]
	for range 100 {
		_, err := c.ReserveUploadURLs(t.Context(), 1, &size, 1)
		require.ErrorIs(t, err, ente.ErrSmallUploadLimitReached)
	}
	require.Equal(t, []smallUploadBucket{before}, state.buckets)
	require.Zero(t, c.UploadURLRepo.(*pendingUploadTestRepository).calls.Load())
	state.buckets[0].end = time.Now().Add(-11 * time.Minute)
	release, err := c.ReserveUploadURLs(t.Context(), 1, &size, 1)
	require.NoError(t, err)
	release()
	release, err = c.ReserveUploadURLs(t.Context(), 2, &size, 1)
	require.NoError(t, err)
	release()
}

func TestFileUploadEntryPointsCheckPendingBeforeStorage(t *testing.T) {
	for _, name := range []string{"single", "legacy batch", "multipart", "legacy multipart"} {
		t.Run(name, func(t *testing.T) {
			fc, _, userID := setupPhotoUploadLimitTest(t)
			r := &pendingUploadTestRepository{}
			r.pending.Store(1000)
			fc.UsageCtrl.UploadURLRepo = r
			var err error
			switch name {
			case "single":
				_, err = fc.GetUploadURLWithMetadata(t.Context(), userID, ente.UploadURLRequest{ContentLength: 1 << 20, ContentMD5: "XUFAKrxLKna5cZ2REBfFkg=="}, ente.Photos, "test")
			case "legacy batch":
				_, err = fc.GetUploadURLs(t.Context(), userID, 50, ente.Photos, false, "test")
			case "multipart":
				_, err = fc.GetMultipartUploadURLWithMetadata(t.Context(), userID, ente.MultipartUploadURLRequest{ContentLength: ente.MinMultipartUploadSize, PartLength: ente.MinMultipartUploadSize}, ente.Photos, "test")
			case "legacy multipart":
				_, err = fc.GetMultipartUploadURLs(t.Context(), userID, 2, ente.Photos, "test")
			}
			require.ErrorIs(t, err, ente.ErrPendingUploadLimitReached)
			require.EqualValues(t, 1, r.calls.Load())
		})
	}
}
