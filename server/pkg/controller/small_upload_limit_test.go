package controller

import (
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/patrickmn/go-cache"
	"github.com/stretchr/testify/require"
)

func TestSmallUploadLimiterConcurrentRequests(t *testing.T) {
	var limiter smallUploadLimiter
	var accepted atomic.Int32
	var wg sync.WaitGroup
	for range 30 {
		wg.Go(func() {
			for range 40 {
				if limiter.allow(1) {
					accepted.Add(1)
				}
			}
		})
	}
	wg.Wait()
	require.EqualValues(t, 1000, accepted.Load())
	require.False(t, limiter.allow(1))
	require.True(t, limiter.allow(2))
}

func TestSmallUploadLimiterRollingWindow(t *testing.T) {
	var limiter smallUploadLimiter
	fillSmallUploadLimit(t, &limiter, 1)
	value, ok := limiter.requests.Get("1")
	require.True(t, ok)
	requests := value.([]time.Time)
	for i := range requests {
		age := 9 * time.Minute
		if i < 500 {
			age = 11 * time.Minute
		}
		requests[i] = time.Now().Add(-age)
	}
	limiter.requests.Set("1", requests, cache.DefaultExpiration)
	for range 500 {
		require.True(t, limiter.allow(1))
	}
	require.False(t, limiter.allow(1))
	value, ok = limiter.requests.Get("1")
	require.True(t, ok)
	require.Len(t, value.([]time.Time), 1000)
}

func TestSmallUploadLimitEntitlements(t *testing.T) {
	for _, tc := range []struct {
		name   string
		paid   bool
		family bool
	}{
		{name: "free"},
		{name: "paid", paid: true},
		{name: "paid family", paid: true, family: true},
		{name: "free family", family: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			fileController, db, userID := setupPhotoUploadLimitTest(t)
			subscriptionUserID := userID
			if tc.family {
				subscriptionUserID = setupUploadLimitFamily(t, db, userID)
			}
			if tc.paid {
				_, err := db.Exec(`UPDATE subscriptions SET product_id = 'photos_yearly' WHERE user_id = $1`, subscriptionUserID)
				require.NoError(t, err)
			}
			c := fileController.UsageCtrl
			fillSmallUploadLimit(t, &c.smallUploads, userID)
			length := int64(32)
			err := c.CanIssueUploadURLs(t.Context(), userID, &length, ente.Photos)
			if tc.paid {
				require.NoError(t, err)
			} else {
				require.ErrorIs(t, err, ente.ErrSmallUploadLimitReached)
			}
		})
	}
}

func TestSmallUploadLimitSizeAndIssuanceScope(t *testing.T) {
	fileController, _, userID := setupPhotoUploadLimitTest(t)
	c := fileController.UsageCtrl
	fillSmallUploadLimit(t, &c.smallUploads, userID)
	for _, size := range []int64{1, 2047, 2048, 2049} {
		err := c.CheckUploadURLRateLimit(userID, &size)
		if size < 2048 {
			require.ErrorIs(t, err, ente.ErrSmallUploadLimitReached)
		} else {
			require.NoError(t, err)
		}
	}
	require.NoError(t, c.CheckUploadURLRateLimit(userID, nil))
	length := int64(32)
	require.NoError(t, c.CanUploadFile(t.Context(), userID, &length, ente.Photos))
}

func TestSmallUploadLimitChecksCachedEligibility(t *testing.T) {
	fileController, _, userID := setupPhotoUploadLimitTest(t)
	c := fileController.UsageCtrl
	c.uploadURLResultCache = map[int64]bool{userID: true}
	fillSmallUploadLimit(t, &c.smallUploads, userID)
	_, err := fileController.GetUploadURLWithMetadata(t.Context(), userID, ente.UploadURLRequest{
		ContentLength: 32, ContentMD5: "XUFAKrxLKna5cZ2REBfFkg==",
	}, ente.Photos, "test")
	require.ErrorIs(t, err, ente.ErrSmallUploadLimitReached)
}

func TestSmallUploadLimitBelowCapSkipsBilling(t *testing.T) {
	c := &UsageController{}
	length := int64(32)
	require.NoError(t, c.CheckUploadURLRateLimit(1, &length))
}

func fillSmallUploadLimit(t *testing.T, limiter *smallUploadLimiter, userID int64) {
	t.Helper()
	for range 1000 {
		require.True(t, limiter.allow(userID))
	}
	require.False(t, limiter.allow(userID))
}
