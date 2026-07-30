package user

import (
	"github.com/ente/museum/ente/details"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

func (c *UserController) GetLockerUsage(ctx *gin.Context, userID int64) (details.LockerUsageResponse, error) {
	user, err := c.GetUser(userID)
	if err != nil {
		return details.LockerUsageResponse{}, stacktrace.Propagate(err, "failed to get user")
	}

	subscriptionAdminID := userID
	subscriptionUserIDs := []int64{userID}
	isFamily := false
	if user.FamilyAdminID != nil {
		isFamily = true
		subscriptionAdminID = *user.FamilyAdminID

		familyMembers, err := c.FamilyController.FamilyRepo.GetMembersWithStatus(*user.FamilyAdminID, repo.ActiveFamilyMemberStatus)
		if err != nil {
			return details.LockerUsageResponse{}, stacktrace.Propagate(err, "failed to fetch family usage scope")
		}

		subscriptionUserIDs = make([]int64, 0, len(familyMembers))
		for _, familyMember := range familyMembers {
			subscriptionUserIDs = append(subscriptionUserIDs, familyMember.MemberUserID)
		}
	}

	lockerUsage, err := c.UsageRepo.GetLockerUsage(ctx, subscriptionUserIDs)
	if err != nil {
		return details.LockerUsageResponse{}, stacktrace.Propagate(err, "failed to fetch locker usage")
	}

	isPaid := false
	if err := c.BillingController.HasActiveSelfOrFamilySubscription(subscriptionAdminID, true); err == nil {
		isPaid = true
	}
	limits := controller.GetLockerLimitsForTier(isPaid)

	result := details.LockerUsageResponse{
		IsPaid:             limits.IsPaid,
		IsFamily:           isFamily,
		UsedFileCount:      lockerUsage.TotalFileCount,
		FileLimit:          limits.FileLimit,
		RemainingFileCount: maxInt64(limits.FileLimit-lockerUsage.TotalFileCount, 0),
		UsedStorage:        lockerUsage.TotalUsage,
		StorageLimit:       limits.StorageLimit,
		RemainingStorage:   maxInt64(limits.StorageLimit-lockerUsage.TotalUsage, 0),
	}
	for _, userLockerUsage := range lockerUsage.Users {
		if userLockerUsage.UserID != userID {
			continue
		}
		result.UserFileCount = userLockerUsage.FileCount
		result.UserStorage = userLockerUsage.Usage
		break
	}

	return result, nil
}

func maxInt64(a, b int64) int64 {
	if a > b {
		return a
	}
	return b
}
