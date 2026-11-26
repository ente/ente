package controller

import (
	"database/sql"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/stretchr/testify/require"
)

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
			c.uploadLimits.state(userID).recordSmall(time.Now(), smallUploadShortLimit)
			length := int64(32)
			release, err := c.ReserveUploadURLs(t.Context(), userID, &length, 1)
			if release != nil {
				release()
			}
			if tc.allowed {
				require.NoError(t, err)
			} else {
				require.ErrorIs(t, err, ente.ErrSmallUploadLimitReached)
			}
		})
	}
}

func TestSmallUploadConcurrentAdmission(t *testing.T) {
	c := newUploadLimitTestController(0)
	size := int64(32)
	var accepted atomic.Int32
	var wg sync.WaitGroup
	for range 30 {
		wg.Go(func() {
			for range 40 {
				release, err := c.ReserveUploadURLs(t.Context(), 1, &size, 1)
				if err == nil {
					accepted.Add(1)
					release()
				} else if !isSmallUploadError(err) {
					t.Errorf("unexpected error: %v", err)
				}
			}
		})
	}
	wg.Wait()
	require.EqualValues(t, 1000, accepted.Load())
}

func TestSmallUploadRollingBudgets(t *testing.T) {
	now := time.Date(2026, 11, 16, 1, 0, 0, 0, time.UTC)
	var state uploadLimitState
	state.recordSmall(now, 1000)
	retryAt := state.smallRetryAt(now, 1)
	require.Equal(t, now.Add(11*time.Minute), retryAt)
	require.Equal(t, retryAt, state.smallRetryAt(now.Add(time.Minute), 1))
	require.False(t, state.smallRetryAt(now.Add(10*time.Minute), 1).IsZero())
	require.True(t, state.smallRetryAt(retryAt, 1).IsZero())
	for i := 1; i < 10; i++ {
		state.recordSmall(now.Add(time.Duration(i)*20*time.Minute), 1000)
	}
	require.Equal(t, now.Add(24*time.Hour+time.Minute), state.smallRetryAt(now.Add(4*time.Hour), 1))
	require.True(t, state.smallRetryAt(now.Add(24*time.Hour+time.Minute), 1000).IsZero())
	require.False(t, state.smallRetryAt(now.Add(24*time.Hour+time.Minute), 1001).IsZero())
	require.True(t, state.smallRetryAt(now.Add(48*time.Hour), 1000).IsZero())
	require.Empty(t, state.buckets)
}

func TestSmallUploadSizeAndIssuanceScope(t *testing.T) {
	c := newUploadLimitTestController(0)
	c.uploadLimits.state(1).recordSmall(time.Now(), 1000)
	for _, size := range []int64{1, 32, 2048, 10239, 10240, 10241, 1000000} {
		release, err := c.ReserveUploadURLs(t.Context(), 1, &size, 1)
		if size < 10240 {
			require.ErrorIs(t, err, ente.ErrSmallUploadLimitReached)
		} else {
			require.NoError(t, err)
			release()
		}
	}
	_, err := c.ReserveUploadURLs(t.Context(), 1, nil, 1)
	require.ErrorIs(t, err, ente.ErrSmallUploadLimitReached)
	fc, _, userID := setupPhotoUploadLimitTest(t)
	state := fc.UsageCtrl.uploadLimits.state(userID)
	state.recordSmall(time.Now(), 1000)
	state.blockedUntil = time.Now().Add(time.Hour)
	length := int64(32)
	require.NoError(t, fc.ValidateUploadEligibility(t.Context(), userID, ente.Photos))
	require.NoError(t, fc.UsageCtrl.CanUploadFile(t.Context(), userID, &length, ente.Photos))
}

func TestSmallUploadEntitlementCacheAndErrors(t *testing.T) {
	for _, paid := range []bool{false, true} {
		t.Run(map[bool]string{false: "free", true: "paid"}[paid], func(t *testing.T) {
			fc, db, userID := setupPhotoUploadLimitTest(t)
			c := fc.UsageCtrl
			state := c.uploadLimits.state(userID)
			state.recordSmall(time.Now(), 1000)
			setPaid := func(p bool) {
				product := ente.FreePlanProductID
				if p {
					product = "photos_yearly"
				}
				_, err := db.Exec(`UPDATE subscriptions SET product_id=$2 WHERE user_id=$1`, userID, product)
				require.NoError(t, err)
			}
			check := func(wantPaid bool) {
				size := int64(32)
				release, err := c.ReserveUploadURLs(t.Context(), userID, &size, 1)
				if wantPaid {
					require.NoError(t, err)
					release()
				} else {
					require.ErrorIs(t, err, ente.ErrSmallUploadLimitReached)
				}
			}
			setPaid(paid)
			closed, err := sql.Open("postgres", "")
			require.NoError(t, err)
			require.NoError(t, closed.Close())
			c.BillingCtrl.BillingRepo.DB = closed
			size := int64(32)
			_, err = c.ReserveUploadURLs(t.Context(), userID, &size, 1)
			require.ErrorContains(t, err, "database is closed")
			require.True(t, state.entitlementExpires.IsZero())
			c.BillingCtrl.BillingRepo.DB = db
			check(paid)
			expiry := state.entitlementExpires
			setPaid(!paid)
			c.BillingCtrl.BillingRepo.DB = closed
			check(paid)
			require.Equal(t, expiry, state.entitlementExpires)
			c.BillingCtrl.BillingRepo.DB = db
			state.entitlementExpires = time.Now().Add(-time.Second)
			check(!paid)
		})
	}
}

func TestSmallUploadChecksCachedEligibility(t *testing.T) {
	fc, _, userID := setupPhotoUploadLimitTest(t)
	c := fc.UsageCtrl
	c.uploadURLResultCache = map[int64]bool{userID: true}
	c.uploadLimits.state(userID).recordSmall(time.Now(), 1000)
	_, err := fc.GetUploadURLWithMetadata(t.Context(), userID, ente.UploadURLRequest{
		ContentLength: 32, ContentMD5: "XUFAKrxLKna5cZ2REBfFkg==",
	}, ente.Photos, "test")
	require.ErrorIs(t, err, ente.ErrSmallUploadLimitReached)
}

func TestSmallUploadBelowBudgetSkipsBilling(t *testing.T) {
	c := newUploadLimitTestController(0)
	c.uploadLimits.state(1).entitlementExpires = time.Time{}
	size := int64(32)
	release, err := c.ReserveUploadURLs(t.Context(), 1, &size, 1)
	require.NoError(t, err)
	release()
	require.Equal(t, 1, c.uploadLimits.state(1).buckets[0].count)
}
