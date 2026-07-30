package storagebonus

import (
	"context"

	entity "github.com/ente/museum/ente/storagebonus"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/sirupsen/logrus"
)

// GetActiveReferralBonusValue returns the storage bonus value for the user
func (c *Controller) GetActiveReferralBonusValue(ctx context.Context, userID int64) (*int64, error) {
	return c.StorageBonus.ActiveStorageSurplusOfType(ctx, userID, []entity.BonusType{entity.Referral, entity.SignUp})
}

// GetStorageBonusDetailResponse returns the storage bonus detail for the user
func (c *Controller) GetStorageBonusDetailResponse(ctx *gin.Context, userID int64) (*entity.GetStorageBonusDetailResponse, error) {

	user, err := c.UserRepo.Get(userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to get user")
	}
	bonusUserID := userID
	if user.FamilyAdminID != nil {
		bonusUserID = *user.FamilyAdminID
		logrus.Info("sharing bonus details of family admin")
	}
	storageBonuses, err := c.StorageBonus.GetStorageBonuses(ctx, bonusUserID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	refStats, err := c.StorageBonus.GetUserReferralStats(ctx, bonusUserID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	hasAppliedCode := false
	// check if storage bonus has type SIGNUP and if it is, set hasAppliedCode to true
	for _, bonus := range storageBonuses {
		if bonus.Type == entity.SignUp {
			hasAppliedCode = true
			break
		}
	}
	totalReferralCount := 0
	totalReferralUpgradeCount := 0
	for _, stat := range refStats {
		totalReferralCount += stat.TotalCount
		totalReferralUpgradeCount += stat.UpgradedCount
	}
	return &entity.GetStorageBonusDetailResponse{
		Bonuses:         storageBonuses,
		ReferralStats:   refStats,
		HasAppliedCode:  hasAppliedCode,
		RefCount:        totalReferralCount,
		RefUpgradeCount: totalReferralUpgradeCount,
	}, nil

}
