package storagebonus

import (
	"database/sql"
	"errors"
	goaway "github.com/TwiN/go-away"
	"github.com/ente/museum/pkg/utils/random"
	"strings"

	"github.com/ente/museum/ente"
	entity "github.com/ente/museum/ente/storagebonus"
	"github.com/ente/museum/pkg/controller/email"
	"github.com/ente/museum/pkg/controller/lock"

	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/storagebonus"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

const (
	codeLength                 = 6
	referralAmountInGb         = 10
	maxClaimableReferralAmount = 2000
	defaultPlanType            = entity.TenGbOnUpgrade
)

// Controller exposes functions to interact with family module
type Controller struct {
	UserRepo                    *repo.UserRepository
	StorageBonus                *storagebonus.Repository
	LockController              *lock.LockController
	CronRunning                 bool
	EmailNotificationController *email.EmailNotificationController
}

func (c *Controller) GetUserReferralView(ctx *gin.Context) (*entity.GetUserReferralView, error) {
	// Get the user id from the context
	userID := auth.GetUserID(ctx.Request.Header)

	// Use goroutines to fetch UserRepo.Get, HasAppliedReferral
	user, err := c.UserRepo.Get(userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to get user")
	}
	appliedReferral, err := c.StorageBonus.HasAppliedReferral(ctx, userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	isFamilyMember := user.FamilyAdminID != nil && *user.FamilyAdminID != userID
	enableApplyCode := !appliedReferral && !isFamilyMember
	// Get the referral code for the user or family admin
	codeUser := userID
	if isFamilyMember {
		codeUser = *user.FamilyAdminID
	}
	referralCode, err2 := c.GetOrCreateReferralCode(ctx, codeUser)
	if err2 != nil {
		return nil, stacktrace.Propagate(err2, "failed to get or create referral code")
	}
	storageClaimed, err2 := c.GetActiveReferralBonusValue(ctx, codeUser)
	if err2 != nil {
		return nil, stacktrace.Propagate(err2, "failed to get storage claimed")
	}
	codeChangeCount, err2 := c.StorageBonus.GetCodeChangeCount(ctx, codeUser)
	if err2 != nil {
		return nil, stacktrace.Propagate(err2, "failed to get code change count")
	}
	// Calculate changes made (count - 1 since first code doesn't count as a change)
	codeChangeAttempts := 0
	if codeChangeCount > 1 {
		codeChangeAttempts = codeChangeCount - 1
	}
	remainingAttempts := max(storagebonus.MaxReferralCodeChangeAllowed-codeChangeAttempts, 0)

	return &entity.GetUserReferralView{
		PlanInfo: entity.PlanInfo{
			IsEnabled:               true,
			PlanType:                defaultPlanType,
			StorageInGB:             referralAmountInGb,
			MaxClaimableStorageInGB: maxClaimableReferralAmount,
		},
		Code:                        referralCode,
		EnableApplyCode:             enableApplyCode,
		IsFamilyMember:              isFamilyMember,
		HasAppliedCode:              appliedReferral,
		ClaimedStorage:              *storageClaimed,
		CodeChangeAttempts:          codeChangeAttempts,
		RemainingCodeChangeAttempts: remainingAttempts,
	}, nil
}

func (c *Controller) ApplyReferralCode(ctx *gin.Context, code string) error {
	// Get user id from the context
	userID := auth.GetUserID(ctx.Request.Header)
	user, err := c.UserRepo.Get(userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to get user")
	}

	codeOwnerID, err := c.StorageBonus.GetUserIDByCode(ctx, code)
	if err != nil {
		return stacktrace.Propagate(err, "failed to get user id by code")
	}
	// Verify that the codeOwnerID is not deleted yet
	_, err = c.UserRepo.Get(*codeOwnerID)
	if err != nil {
		if errors.Is(err, ente.ErrUserDeleted) {
			return stacktrace.Propagate(entity.InvalidCodeErr, "code belongs to deleted user")
		}
		return stacktrace.Propagate(err, "failed to get user")
	}

	if user.FamilyAdminID != nil && userID != *user.FamilyAdminID {
		return stacktrace.Propagate(entity.CanNotApplyCodeErr, "user is member of a family plan")
	}

	err = c.StorageBonus.TrackReferralAndInviteeBonus(ctx, userID, *codeOwnerID, defaultPlanType)
	if err != nil {
		return stacktrace.Propagate(err, "failed to apply code")
	}
	return nil
}

func (c *Controller) GetOrCreateReferralCode(ctx *gin.Context, userID int64) (*string, error) {
	referralCode, err := c.StorageBonus.GetCode(ctx, userID)
	if err != nil {
		if !errors.Is(err, sql.ErrNoRows) {
			return nil, stacktrace.Propagate(err, "failed to get storagebonus code")
		}
		code, err := random.GenerateAlphaNumString(codeLength)
		if err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		err = c.StorageBonus.InsertCode(ctx, userID, code)
		if err != nil {
			return nil, stacktrace.Propagate(err, "failed to insert storagebonus code")
		}
		referralCode = &code
	}
	return referralCode, nil
}

func (c *Controller) UpdateReferralCode(ctx *gin.Context, userID int64, code string, isAdminEdit bool) error {
	code = strings.ToUpper(code)
	if !random.IsAlphanumeric(code) {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("code is not alphanumeric"), "")
	}
	if len(code) < 4 || len(code) > 20 {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("code length should be between 4 and 8"), "")
	}

	// Check if the code contains any offensive language using the go-away library
	if goaway.IsProfane(code) {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("Referral code contains offensive language and cannot be used"), "")
	}

	err := c.StorageBonus.AddNewCode(ctx, userID, code, isAdminEdit)
	if err != nil {
		return stacktrace.Propagate(err, "failed to update referral code")
	}
	return nil
}
