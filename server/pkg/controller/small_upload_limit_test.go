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
		name           string
		paid           bool
		family         bool
		provider       ente.PaymentProvider
		subExpiry      time.Duration
		bonusType      string
		expiredBonus   bool
		revokedBonus   bool
		permanentBonus bool
		selfHosted     bool
		allowed        bool
	}{
		{name: "free"},
		{name: "paid", paid: true, allowed: true},
		{name: "paid family", paid: true, family: true, allowed: true},
		{name: "free family", family: true},
		{name: "renewal grace", paid: true, subExpiry: -7 * 24 * time.Hour, allowed: true},
		{name: "appstore grace", paid: true, provider: ente.AppStore, subExpiry: -4 * 24 * time.Hour, allowed: true},
		{name: "paypal grace", paid: true, provider: ente.Paypal, subExpiry: -4 * 24 * time.Hour, allowed: true},
		{name: "playstore grace", paid: true, provider: ente.PlayStore, subExpiry: -4 * 24 * time.Hour, allowed: true},
		{name: "expired appstore grace", paid: true, provider: ente.AppStore, subExpiry: -6 * 24 * time.Hour},
		{name: "bitpay without grace", paid: true, provider: ente.BitPay, subExpiry: -time.Hour},
		{name: "expired subscription", paid: true, subExpiry: -30 * 24 * time.Hour},
		{name: "expired family subscription", paid: true, family: true, subExpiry: -30 * 24 * time.Hour},
		{name: "active paid bonus", bonusType: "ADD_ON_SUPPORT", allowed: true},
		{name: "permanent paid bonus", bonusType: "ADD_ON_SUPPORT", permanentBonus: true, allowed: true},
		{name: "expired paid bonus", bonusType: "ADD_ON_SUPPORT", expiredBonus: true},
		{name: "revoked paid bonus", bonusType: "ADD_ON_SUPPORT", revokedBonus: true},
		{name: "active family bonus", family: true, bonusType: "ADD_ON_SUPPORT", allowed: true},
		{name: "revoked family bonus", family: true, bonusType: "ADD_ON_SUPPORT", revokedBonus: true},
		{name: "expired plan with active bonus", paid: true, subExpiry: -30 * 24 * time.Hour, bonusType: "ADD_ON_SUPPORT", allowed: true},
		{name: "referral bonus", bonusType: "REFERRAL"},
		{name: "self hosted", selfHosted: true, allowed: true},
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
			if tc.subExpiry != 0 {
				_, err := db.Exec(`UPDATE subscriptions SET expiry_time = $2 WHERE user_id = $1`, subscriptionUserID, time.Now().Add(tc.subExpiry).UnixMicro())
				require.NoError(t, err)
			}
			if tc.provider != "" {
				_, err := db.Exec(`UPDATE subscriptions SET payment_provider = $2 WHERE user_id = $1`, subscriptionUserID, tc.provider)
				require.NoError(t, err)
			}
			if tc.bonusType != "" {
				validTill := time.Now().Add(time.Hour).UnixMicro()
				if tc.expiredBonus {
					validTill = time.Now().Add(-time.Hour).UnixMicro()
				} else if tc.permanentBonus {
					validTill = 0
				}
				_, err := db.Exec(`INSERT INTO storage_bonus(bonus_id, user_id, storage, type, valid_till, is_revoked)
					VALUES ('small-upload-bonus', $1, $2, $3, $4, $5)`, subscriptionUserID, 1<<30, tc.bonusType, validTill, tc.revokedBonus)
				require.NoError(t, err)
			}
			if tc.selfHosted {
				_, err := db.Exec(`DELETE FROM users WHERE user_id = 1`)
				require.NoError(t, err)
			}
			c := fileController.UsageCtrl
			fillSmallUploadLimit(t, &c.smallUploads, userID)
			length := int64(32)
			err := c.CheckUploadURLRateLimit(userID, &length)
			if tc.allowed {
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
