package family

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/url"
	"slices"
	"strings"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/billing"
	emailUtil "github.com/ente/museum/pkg/utils/email"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/sirupsen/logrus"
	"github.com/spf13/viper"
)

const (
	InviteTokenLength = 32
	InviteTemplate    = "family_invited.html"
	AcceptedTemplate  = "family_accepted.html"
	LeftTemplate      = "family_left.html"
	RemovedTemplate   = "family_removed.html"

	HappyHeaderImage = "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"
	SadHeaderImage   = "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"
)

// CreateFamily creates a family with current user as admin member
func (c *Controller) CreateFamily(ctx context.Context, adminUserID int64) error {
	err := c.BillingCtrl.HasActiveSelfOrFamilySubscription(adminUserID, true)
	if err != nil {
		return stacktrace.Propagate(ente.ErrNoActiveSubscription, "you must be on a paid plan")
	}
	adminUser, err := c.UserRepo.Get(adminUserID)
	if err != nil {
		return err
	}
	if adminUser.FamilyAdminID != nil {
		if *adminUser.FamilyAdminID != adminUserID {
			return stacktrace.Propagate(ente.ErrBadRequest, "Must not be a part of a different family")
		} else {
			logrus.Info(fmt.Sprintf("family is already created for %d", adminUserID))
			return nil
		}
	}
	err = c.FamilyRepo.CreateFamily(ctx, adminUserID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}

// InviteMember invites a user to join the family plan of admin User
func (c *Controller) InviteMember(ctx *gin.Context, adminUserID int64, email string, storageLimit *int64) error {
	err := c.BillingCtrl.HasActiveSelfOrFamilySubscription(adminUserID, true)
	if err != nil {
		return stacktrace.Propagate(ente.ErrNoActiveSubscription, "you must be on a paid plan")
	}
	adminUser, err := c.UserRepo.Get(adminUserID)
	if err != nil {
		return err
	}
	if adminUser.FamilyAdminID == nil {
		return stacktrace.Propagate(ente.ErrBadRequest, "admin needs to create a family before inviting members")
	} else if *adminUser.FamilyAdminID != adminUserID {
		return stacktrace.Propagate(ente.ErrBadRequest, "must be an admin to invite members")
	}

	members, err := c.FamilyRepo.GetMembersWithStatus(adminUserID, repo.ActiveOrInvitedFamilyMemberStatus)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	potentialMemberID, err := c.UserLookup.LookupUserID(adminUserID, email)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			if len(members) >= maxFamilyMemberLimit {
				return stacktrace.Propagate(ente.ErrFamilySizeLimitReached, "family invite limit exceeded")
			}
			return stacktrace.Propagate(ente.ErrNotFound, "invited member is not on ente")
		} else {
			return stacktrace.Propagate(err, "")
		}
	}
	if potentialMemberID == adminUserID {
		return stacktrace.Propagate(ente.ErrCanNotInviteUserAlreadyInFamily, "Can not self invite")
	}
	if len(members) >= maxFamilyMemberLimit && !slices.ContainsFunc(members, func(member ente.FamilyMember) bool {
		return member.MemberUserID == potentialMemberID && member.Status == ente.INVITED
	}) {
		return stacktrace.Propagate(ente.ErrFamilySizeLimitReached, "family invite limit exceeded")
	}

	potentialMemberUser, err := c.UserRepo.Get(potentialMemberID)
	if err != nil {
		return err
	}

	if potentialMemberUser.FamilyAdminID != nil {
		return stacktrace.Propagate(ente.ErrCanNotInviteUserAlreadyInFamily, "invited member is already a part of family")
	}
	potentialMemberSub, err := c.BillingCtrl.GetSubscription(ctx, potentialMemberID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if billing.IsActivePaidPlan(potentialMemberSub) && !potentialMemberSub.Attributes.IsCancelled {
		return stacktrace.Propagate(ente.ErrCanNotInviteUserWithPaidPlan, "")
	}

	inviteToken := auth.GenerateURLSafeRandomString(InviteTokenLength)

	activeInviteToken, err := c.FamilyRepo.AddMemberInvite(ctx, adminUserID, potentialMemberUser.ID, inviteToken, storageLimit)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	go func(token string) {
		notificationErr := c.sendNotification(ctx, adminUserID, potentialMemberID, ente.INVITED, &token)
		if notificationErr != nil {
			logrus.WithError(notificationErr).Error("family-plan invite notification failed")
		}
	}(activeInviteToken)
	return nil
}

// RemoveMember verify admin -> memberID mapping & revokes the member's access from admin plan
func (c *Controller) RemoveMember(ctx context.Context, adminID int64, id uuid.UUID) error {
	familyMember, err := c.FamilyRepo.GetMemberById(ctx, id)
	if err != nil {
		return stacktrace.Propagate(err, "failed to find member for given id")
	}
	if familyMember.AdminUserID != adminID {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "ops can be performed by family admin only")
	}
	if familyMember.Status == ente.REMOVED {
		return nil
	}
	if familyMember.Status != ente.ACCEPTED {
		return stacktrace.Propagate(ente.ErrBadRequest, "can not remove member from %s state", familyMember.Status)
	}
	err = c.FamilyRepo.RemoveMember(ctx, adminID, familyMember.MemberUserID, ente.REMOVED)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if err = c.clearFamilyCustomDomain(ctx, familyMember.MemberUserID); err != nil {
		return stacktrace.Propagate(err, "")
	}
	go func() {
		notificationErr := c.sendNotification(ctx, adminID, familyMember.MemberUserID, ente.REMOVED, nil)
		if notificationErr != nil {
			logrus.WithError(notificationErr).Error("family-plan remove notification failed")
		}
	}()
	return nil
}

// RevokeInvite revokes a family invite which is not accepted yet
func (c *Controller) RevokeInvite(ctx context.Context, adminID int64, id uuid.UUID) error {
	familyMember, err := c.FamilyRepo.GetMemberById(ctx, id)
	if err != nil {
		return stacktrace.Propagate(err, "failed to find member for given id")
	}
	if familyMember.AdminUserID != adminID {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "ops can be performed by family admin only")
	}
	if familyMember.Status == ente.REVOKED {
		return nil
	}
	if familyMember.Status != ente.INVITED {
		return stacktrace.Propagate(ente.ErrBadRequest, "can not revoke invite in current state")
	}
	err = c.FamilyRepo.RevokeInvite(ctx, adminID, familyMember.MemberUserID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}

func (c *Controller) CloseFamily(ctx context.Context, adminID int64) error {
	logger := logrus.WithField("adminID", adminID).WithField("operation", "CloseFamily")
	err := c.removeMembers(ctx, adminID, logger)
	if err != nil {
		return stacktrace.Propagate(err, "failed to remove members")
	}
	err = c.FamilyRepo.CloseFamily(ctx, adminID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}

// ModifyMemberStorage allows admin user to update the storageLimit for a member in the family
func (c *Controller) ModifyMemberStorage(ctx context.Context, actorUserID int64, id uuid.UUID, storageLimit *int64) error {
	member, err := c.FamilyRepo.GetMemberById(ctx, id)
	if err != nil {
		return stacktrace.Propagate(err, "Couldn't fetch Family Member")
	}

	if member.AdminUserID != actorUserID {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "you do not have sufficient permission")
	}

	if member.IsAdmin {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("can not limit admin storage"), "cannot modify admin storage limit")
	}

	if member.Status != ente.ACCEPTED {
		return stacktrace.Propagate(ente.ErrBadRequest, "user is not a part of family")
	}

	// gets admin subscription in order to get the size of total storage quota (including bonus)
	if storageLimit != nil {
		familyMembersData, err := c.FetchMembersForAdminID(ctx, member.AdminUserID)
		if err != nil {
			return stacktrace.Propagate(ente.ErrBadRequest, "couldn't get active subscription")
		}
		totalFamilyStorage := familyMembersData.Storage + familyMembersData.AdminBonus
		if *storageLimit > totalFamilyStorage {
			return stacktrace.Propagate(ente.ErrStorageLimitExceeded, "potential storage limit is more than subscription storage")
		}

		// Handle if the admin user tries reducing the storage Limit
		// and the members Usage is more than the potential storage Limit
		memberUsage, memUsageErr := c.UsageRepo.GetUsage(member.MemberUserID)
		if memUsageErr != nil {
			return stacktrace.Propagate(memUsageErr, "Couldn't find members storage usage")
		}

		if memberUsage > *storageLimit {
			return stacktrace.Propagate(ente.NewBadRequestWithMessage("Failed to reduce storage"), "User's current usage is more")
		}
	}

	modifyStorageErr := c.FamilyRepo.ModifyMemberStorage(ctx, actorUserID, member.ID, storageLimit)
	if modifyStorageErr != nil {
		return stacktrace.Propagate(modifyStorageErr, "Failed to modify members storage")
	}

	return nil
}

func (c *Controller) sendNotification(ctx context.Context, adminUserID int64, memberUserID int64, newStatus ente.MemberStatus, inviteToken *string) error {
	adminUser, err := c.UserRepo.Get(adminUserID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	memberUser, err := c.UserRepo.Get(memberUserID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	templateData := map[string]interface{}{
		"MemberEmailID": memberUser.Email,
		"AdminEmailID":  adminUser.Email,
	}
	if newStatus == ente.INVITED {
		if inviteToken == nil {
			return stacktrace.Propagate(fmt.Errorf("invite token can not be nil"), "")
		}
		accountsURL := strings.TrimRight(viper.GetString("apps.accounts"), "/")
		templateData["FamilyInviteLink"] = fmt.Sprintf("%s/family#inviteToken=%s", accountsURL, url.QueryEscape(*inviteToken))
	}
	var templateName, emailTo, title string
	var inlineImages []map[string]interface{}
	inlineImage := make(map[string]interface{})
	inlineImage["mime_type"] = "image/png"
	inlineImage["cid"] = "header-image"

	if newStatus == ente.INVITED {
		templateName = InviteTemplate
		title = "You've been invited to join a family on Ente!"
		emailTo = memberUser.Email
		inlineImage["content"] = HappyHeaderImage
	} else if newStatus == ente.REMOVED {
		emailTo = memberUser.Email
		templateName = RemovedTemplate
		title = "You have been removed from the family account on Ente"
		inlineImage["content"] = SadHeaderImage
	} else if newStatus == ente.LEFT {
		emailTo = adminUser.Email
		templateName = LeftTemplate
		title = fmt.Sprintf("%s has left your family on Ente", memberUser.Email)
		inlineImage["content"] = SadHeaderImage
	} else if newStatus == ente.ACCEPTED {
		emailTo = adminUser.Email
		templateName = AcceptedTemplate
		title = fmt.Sprintf("%s has accepted your invitation!", memberUser.Email)
		inlineImage["content"] = HappyHeaderImage
	} else {
		return stacktrace.Propagate(fmt.Errorf("unsupported status %s", newStatus), "")
	}
	inlineImages = append(inlineImages, inlineImage)
	err = emailUtil.SendTemplatedEmail([]string{emailTo}, "ente", "team@ente.com",
		title, templateName, templateData, inlineImages)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}
