package family

import (
	"context"
	"errors"
	"fmt"

	"github.com/ente/museum/pkg/controller/usercache"
	remoteStoreRepo "github.com/ente/museum/pkg/repo/remotestore"
	"github.com/ente/museum/pkg/utils/time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/repo"
	"github.com/sirupsen/logrus"

	"github.com/ente/stacktrace"
)

const (
	// maxFamilyMemberLimit number of folks who can be part of a family
	maxFamilyMemberLimit = 6
)

// Controller exposes functions to interact with family module
type Controller struct {
	BillingCtrl     *controller.BillingController
	UserLookup      controller.UserLookup
	UserRepo        *repo.UserRepository
	FamilyRepo      *repo.FamilyRepository
	UserCacheCtrl   *usercache.Controller
	UsageRepo       *repo.UsageRepository
	RemoteStoreRepo *remoteStoreRepo.Repository
}

// FetchMembers return list of members who are part of a family plan
func (c *Controller) FetchMembers(ctx context.Context, userID int64) (ente.FamilyMemberResponse, error) {
	user, err := c.UserRepo.Get(userID)
	if err != nil {
		return ente.FamilyMemberResponse{}, stacktrace.Propagate(err, "")
	}
	if user.FamilyAdminID == nil {
		return ente.FamilyMemberResponse{}, stacktrace.Propagate(ente.ErrBadRequest, "user is not part of any family plan")
	}
	return c.FetchMembersForAdminID(ctx, *user.FamilyAdminID)
}

func (c *Controller) FetchMembersForAdminID(ctx context.Context, familyAdminID int64) (ente.FamilyMemberResponse, error) {
	familyMembers, err := c.FamilyRepo.GetMembersWithStatus(familyAdminID, repo.ActiveOrInvitedFamilyMemberStatus)
	if err != nil {
		return ente.FamilyMemberResponse{}, stacktrace.Propagate(err, "")
	}
	memberUserIDs := make([]int64, 0)
	for _, familyMember := range familyMembers {
		memberUserIDs = append(memberUserIDs, familyMember.MemberUserID)
	}
	if len(memberUserIDs) == 0 {
		return ente.FamilyMemberResponse{}, stacktrace.Propagate(errors.New("member could can not be zero"), "")
	}

	usersUsageWithSubData, err := c.UserRepo.GetUserUsageWithSubData(ctx, memberUserIDs)
	if err != nil {
		return ente.FamilyMemberResponse{}, err
	}
	var adminSubStorage, adminSubExpiryTime int64
	for i := 0; i < len(familyMembers); i++ {
		member := &familyMembers[i]
		if member.Status == ente.ACCEPTED || member.Status == ente.SELF {
			member.UserID = &member.MemberUserID
		}
		for _, userUsageData := range usersUsageWithSubData {
			if member.MemberUserID == userUsageData.UserID {
				member.Email = *userUsageData.Email
				// return usage only if the member is part of family group
				if member.Status == ente.ACCEPTED || member.Status == ente.SELF {
					member.Usage = userUsageData.StorageConsumed
				}
				if member.IsAdmin {
					adminSubStorage = userUsageData.Storage
					adminSubExpiryTime = userUsageData.ExpiryTime
				}
			}
		}
	}
	bonus, err := c.UserCacheCtrl.GetActiveStorageBonus(ctx, familyAdminID)
	if err != nil {
		return ente.FamilyMemberResponse{}, err
	}
	adminUsableBonus := int64(0)
	if adminSubExpiryTime < time.Microseconds() {
		adminUsableBonus = bonus.GetUsableBonus(0)
	} else {
		adminUsableBonus = bonus.GetUsableBonus(adminSubStorage)
	}

	return ente.FamilyMemberResponse{
		Members:    familyMembers,
		Storage:    adminSubStorage, // family plan storage
		ExpiryTime: adminSubExpiryTime,
		AdminBonus: adminUsableBonus,
	}, nil
}

func (c *Controller) ResetUserFamilyAccess(ctx context.Context, userID int64, logger *logrus.Entry) error {
	user, err := c.UserRepo.Get(userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if user.FamilyAdminID == nil {
		logger.Info("not part of any family, declining any pending invite")
		err = c.FamilyRepo.DeclineAnyPendingInvite(ctx, userID)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
	} else if *user.FamilyAdminID != userID {
		logger.Info("user is part of family as member/child, leaving family")
		err = c.LeaveFamily(ctx, userID)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
	} else {
		logger.Info("user is a family admin, revoking invites & removing members")
		removeErr := c.removeMembers(ctx, userID, logger)
		if removeErr != nil {
			return removeErr
		}
	}
	return nil
}

func (c *Controller) HandleAccountDeletion(ctx context.Context, userID int64, logger *logrus.Entry) error {
	return c.ResetUserFamilyAccess(ctx, userID, logger)
}

func (c *Controller) removeMembers(ctx context.Context, adminID int64, logger *logrus.Entry) error {
	members, err := c.FetchMembersForAdminID(ctx, adminID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	for _, member := range members.Members {
		if member.IsAdmin {
			continue
		} else if member.Status == ente.ACCEPTED {
			logger.Info(fmt.Sprintf("removing memeber_id %d", member.MemberUserID))
			err = c.RemoveMember(ctx, adminID, member.ID)
			if err != nil {
				return stacktrace.Propagate(err, "")
			}
		} else if member.Status == ente.INVITED {
			logger.Info(fmt.Sprintf("revoking invite member_id %d", member.MemberUserID))
			err = c.RevokeInvite(ctx, adminID, member.ID)
			if err != nil {
				return stacktrace.Propagate(err, "")
			}
		} else {
			logger.WithField("member", member).Error("unxpected state during account deletion")
		}
	}
	return nil
}

func (c *Controller) clearFamilyCustomDomain(ctx context.Context, userID int64) error {
	if c.RemoteStoreRepo == nil {
		return nil
	}
	domain, err := c.RemoteStoreRepo.GetDomain(ctx, userID)
	if err != nil {
		logrus.WithField("user_id", userID).WithError(err).Warn("family custom domain fetch failed")
		return nil
	}
	if domain == nil || *domain == "" {
		return nil
	}
	_, _, isPointer, parseErr := ente.ParseFamilyCustomDomainPointer(*domain)
	if parseErr != nil {
		logrus.WithFields(logrus.Fields{
			"user_id": userID,
			"domain":  *domain,
		}).WithError(parseErr).Warn("family custom domain parse failed")
		return nil
	}
	if !isPointer {
		return nil
	}
	return c.RemoteStoreRepo.RemoveKey(ctx, userID, string(ente.CustomDomain))
}
