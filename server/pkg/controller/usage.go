package controller

import (
	"context"
	"errors"
	"sync"

	"github.com/ente/museum/ente"
	bonus "github.com/ente/museum/ente/storagebonus"
	"github.com/ente/museum/pkg/controller/storagebonus"
	"github.com/ente/museum/pkg/controller/usercache"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/stacktrace"
)

type UsageController struct {
	mu                sync.Mutex
	BillingCtrl       *BillingController
	StorageBonusCtrl  *storagebonus.Controller
	UserCacheCtrl     *usercache.Controller
	UsageRepo         *repo.UsageRepository
	UserRepo          *repo.UserRepository
	FamilyRepo        *repo.FamilyRepository
	FileRepo          *repo.FileRepository
	UploadResultCache map[int64]bool
}

const lockerFreeFileLimit = 100
const lockerPaidFileLimit = 1000
const lockerFreeStorageLimit = 1 * 1024 * 1024 * 1024
const lockerPaidStorageLimit = 10 * 1024 * 1024 * 1024

const hundredMBInBytes = 100 * 1024 * 1024

type LockerLimits struct {
	IsPaid       bool
	FileLimit    int64
	StorageLimit int64
}

func GetLockerLimitsForTier(isPaid bool) LockerLimits {
	limits := LockerLimits{
		IsPaid:       isPaid,
		FileLimit:    int64(lockerFreeFileLimit),
		StorageLimit: int64(lockerFreeStorageLimit),
	}
	if isPaid {
		limits.FileLimit = int64(lockerPaidFileLimit)
		limits.StorageLimit = int64(lockerPaidStorageLimit)
	}
	return limits
}

func (c *UsageController) CanUploadFile(ctx context.Context, userID int64, size *int64, app ente.App) error {
	if app != ente.Locker && (size == nil || *size < hundredMBInBytes) {
		c.mu.Lock()
		canUpload, ok := c.UploadResultCache[userID]
		c.mu.Unlock()
		if ok && canUpload {
			go func() {
				_ = c.checkAndUpdateCache(ctx, userID, size, app)
			}()
			return nil
		}
	}
	return c.checkAndUpdateCache(ctx, userID, size, app)
}

func (c *UsageController) checkAndUpdateCache(ctx context.Context, userID int64, size *int64, app ente.App) error {
	err := c.canUploadFile(ctx, userID, size, app)
	c.mu.Lock()
	c.UploadResultCache[userID] = err == nil
	c.mu.Unlock()
	return err
}

func (c *UsageController) canUploadFile(ctx context.Context, userID int64, size *int64, app ente.App) error {
	familyAdminID, err := c.UserRepo.GetFamilyAdminID(userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	var subscriptionAdminID int64
	var subscriptionUserIDs []int64

	var memberStorageLimit *int64
	if familyAdminID != nil {
		familyMembers, err := c.FamilyRepo.GetMembersWithStatus(*familyAdminID, repo.ActiveFamilyMemberStatus)
		if err != nil {
			return stacktrace.Propagate(err, "failed to fetch family members")
		}
		subscriptionAdminID = *familyAdminID
		for _, familyMember := range familyMembers {
			subscriptionUserIDs = append(subscriptionUserIDs, familyMember.MemberUserID)
			if familyMember.MemberUserID == userID && familyMember.MemberUserID != *familyAdminID {
				memberStorageLimit = familyMember.StorageLimit
			}
		}
	} else {
		subscriptionAdminID = userID
		subscriptionUserIDs = []int64{userID}
	}

	var subStorage int64
	var bonus *bonus.ActiveStorageBonus
	sub, err := c.BillingCtrl.GetActiveSubscription(subscriptionAdminID)
	if err != nil {
		subStorage = 0
		if errors.Is(err, ente.ErrNoActiveSubscription) {
			bonusRes, bonErr := c.UserCacheCtrl.GetActiveStorageBonus(ctx, subscriptionAdminID)
			if bonErr != nil {
				return stacktrace.Propagate(bonErr, "failed to get bonus data")
			}
			if bonusRes.GetMaxExpiry() <= 0 {
				return stacktrace.Propagate(err, "all bonus & plan expired")
			}
			bonus = bonusRes
		} else {
			return stacktrace.Propagate(err, "")
		}
	} else {
		subStorage = sub.Storage
	}
	var lockerUsage *repo.LockerUsage
	var lUsageErr error
	if app == ente.Locker {
		lockerUsage, lUsageErr = c.UsageRepo.GetLockerUsage(ctx, subscriptionUserIDs)
		if lUsageErr != nil {
			return stacktrace.Propagate(lUsageErr, "failed to fetch locker usage")
		}

		isPaidUser := false
		if err := c.BillingCtrl.HasActiveSelfOrFamilySubscription(subscriptionAdminID, true); err == nil {
			isPaidUser = true
		}

		limits := GetLockerLimitsForTier(isPaidUser)

		if lockerUsage.TotalFileCount >= limits.FileLimit {
			return stacktrace.Propagate(&ente.ErrFileLimitReached, "")
		}

		projectedLockerUsage := lockerUsage.TotalUsage
		if size != nil {
			projectedLockerUsage += *size
		}
		if projectedLockerUsage >= limits.StorageLimit {
			return stacktrace.Propagate(ente.ErrStorageLimitExceeded, "locker storage limit exceeded (limit %d, usage %d)", limits.StorageLimit, projectedLockerUsage)
		}
		// Locker uploads should not be blocked by Photos subscription limits.
		return nil
	}

	usage, err := c.UsageRepo.GetCombinedUsage(ctx, subscriptionUserIDs)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	newUsage := usage

	if size != nil {
		newUsage += *size
		subStorage += StorageOverflowAboveSubscriptionLimit
	}
	if newUsage > subStorage {
		if bonus == nil {
			bonus, err = c.UserCacheCtrl.GetActiveStorageBonus(ctx, subscriptionAdminID)
			if err != nil {
				return stacktrace.Propagate(err, "failed to get storage bonus")
			}
		}
		var eligibleBonus = bonus.GetUsableBonus(subStorage)
		if newUsage > (subStorage + eligibleBonus) {
			if lockerUsage == nil && lUsageErr == nil {
				lockerUsage, lUsageErr = c.UsageRepo.GetLockerUsage(ctx, subscriptionUserIDs)
				if lUsageErr != nil {
					return stacktrace.Propagate(lUsageErr, "failed to fetch locker usage")
				}
			}
			if lockerUsage == nil || (newUsage-lockerUsage.TotalUsage) > (subStorage+eligibleBonus) {
				return stacktrace.Propagate(ente.ErrStorageLimitExceeded, "subscription Storage Limit Exceeded (limit %d, usage %d, bonus %d) for admin %d", subStorage, usage, eligibleBonus, subscriptionAdminID)
			}
		}
	}

	if subscriptionAdminID != userID && memberStorageLimit != nil {
		memberUsage, memberUsageErr := c.UsageRepo.GetUsage(userID)
		if memberUsageErr != nil {
			return stacktrace.Propagate(memberUsageErr, "Couldn't get Members Usage")
		}
		if size != nil {
			memberUsage += *size
		}
		if memberUsage > (*memberStorageLimit + StorageOverflowAboveSubscriptionLimit) {
			return stacktrace.Propagate(ente.ErrStorageLimitExceeded, "member Storage Limit Exceeded (limit %d, usage %d)", *memberStorageLimit, memberUsage)

		}
	}
	return nil
}
