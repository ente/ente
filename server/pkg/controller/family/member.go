package family

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
	"github.com/sirupsen/logrus"
)

func (c *Controller) LeaveFamily(ctx context.Context, userID int64) error {
	user, err := c.UserRepo.Get(userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if user.FamilyAdminID == nil {
		logrus.WithField("user_id", userID).Info("not part of any family group")
		return nil
	}
	if *user.FamilyAdminID == userID {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "admin can not leave the family group")
	}
	err = c.FamilyRepo.RemoveMember(ctx, *user.FamilyAdminID, userID, ente.LEFT)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if err = c.clearFamilyCustomDomain(ctx, userID); err != nil {
		return stacktrace.Propagate(err, "")
	}
	go func() {
		notificationErr := c.sendNotification(ctx, *user.FamilyAdminID, userID, ente.LEFT, nil)
		if notificationErr != nil {
			logrus.WithError(notificationErr).Error("family-plan: left notification failed")
		}
	}()
	return nil
}

func (c *Controller) InviteInfo(ctx context.Context, token string) (ente.InviteInfoResponse, error) {
	familyMember, err := c.FamilyRepo.GetInvite(token)
	if err != nil && errors.Is(err, sql.ErrNoRows) {
		return ente.InviteInfoResponse{}, stacktrace.Propagate(err, "invite not found")
	} else if err != nil {
		return ente.InviteInfoResponse{}, stacktrace.Propagate(err, "failed to fetch invite info")
	}

	if familyMember.Status != ente.INVITED {
		return ente.InviteInfoResponse{}, stacktrace.Propagate(ente.ErrBadRequest, "invited is not valid any more: %s ", familyMember.Status)
	}
	adminUser, err := c.UserRepo.Get(familyMember.AdminUserID)
	if err != nil {
		return ente.InviteInfoResponse{}, stacktrace.Propagate(err, "failed to fetch user")

	}
	if adminUser.FamilyAdminID == nil || *adminUser.FamilyAdminID != adminUser.ID {
		return ente.InviteInfoResponse{}, stacktrace.Propagate(fmt.Errorf("inviter is no longer a admin of family plam "), "")
	}
	return ente.InviteInfoResponse{
		ID:         familyMember.ID,
		AdminEmail: adminUser.Email,
	}, nil
}

func (c *Controller) AcceptInvite(ctx context.Context, token string) (ente.AcceptInviteResponse, error) {
	familyMember, err := c.FamilyRepo.GetInvite(token)
	if err != nil {
		return ente.AcceptInviteResponse{}, stacktrace.Propagate(err, "invite not found")
	}
	adminUser, err := c.UserRepo.Get(familyMember.AdminUserID)
	if err != nil {
		return ente.AcceptInviteResponse{}, stacktrace.Propagate(err, "failed to fetch user")
	}
	if adminUser.FamilyAdminID == nil || *adminUser.FamilyAdminID != adminUser.ID {
		return ente.AcceptInviteResponse{}, stacktrace.Propagate(fmt.Errorf("inviter is no longer a admin of family plam "), "")
	}

	if familyMember.Status != ente.ACCEPTED {
		if familyMember.Status == ente.INVITED {
			err = c.FamilyRepo.AcceptInvite(ctx, familyMember.AdminUserID, familyMember.MemberUserID, token)
			if err != nil {
				return ente.AcceptInviteResponse{}, stacktrace.Propagate(err, "")
			}
			go func() {
				notificationErr := c.sendNotification(ctx, familyMember.AdminUserID, familyMember.MemberUserID, ente.ACCEPTED, nil)
				if notificationErr != nil {
					logrus.WithError(notificationErr).Error("family-plan: accepted notification failed")
				}
			}()
		} else {
			return ente.AcceptInviteResponse{}, stacktrace.Propagate(ente.ErrInvalidPassword, "invited state is not valid any more: %s ", familyMember.Status)
		}
	}

	bonus, bonusErr := c.UserCacheCtrl.GetActiveStorageBonus(ctx, adminUser.ID)
	if bonusErr != nil {
		return ente.AcceptInviteResponse{}, bonusErr
	}
	adminSubscription, subErr := c.BillingCtrl.GetActiveSubscription(adminUser.ID)
	if subErr != nil && !errors.Is(subErr, ente.ErrNoActiveSubscription) {
		return ente.AcceptInviteResponse{}, stacktrace.Propagate(subErr, "")
	}
	adminUsableBonus := int64(0)

	if subErr != nil && errors.Is(subErr, ente.ErrNoActiveSubscription) {
		adminUsableBonus = bonus.GetUsableBonus(0)
	} else {
		adminUsableBonus = bonus.GetUsableBonus(adminSubscription.Storage)
	}

	return ente.AcceptInviteResponse{
		AdminEmail: adminUser.Email,
		Storage:    adminSubscription.Storage + adminUsableBonus,
		ExpiryTime: adminSubscription.ExpiryTime,
	}, nil
}
