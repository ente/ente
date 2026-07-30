package storagebonus

import (
	"context"

	"github.com/ente/museum/pkg/utils/time"
	"github.com/sirupsen/logrus"
)

// PaymentUpgradeOrDowngradeCron cron which returns if CronRunning is true and if false,
// it acquires a lock using the lock controller and sets CronRunning to true.
// It then runs the cron and sets CronRunning to false.
func (c *Controller) PaymentUpgradeOrDowngradeCron() {
	cronName := "payment_upgrade_or_downgrade"
	logger := logrus.WithField("cron", cronName)
	ctx := context.Background()
	if c.CronRunning {
		return
	}
	if !c.LockController.TryLock("payment_upgrade_or_downgrade", time.MicrosecondsAfterMinutes(10)) {
		return
	}
	c.CronRunning = true
	defer func() {
		c.LockController.ReleaseLock("payment_upgrade_or_downgrade")
		c.CronRunning = false
	}()
	bonusCandidate, err := c.StorageBonus.GetReferredForUpgradeBonus(ctx)
	if err != nil {
		logger.WithError(err).Error("failed to GetReferredForUpgradeBonus")
		return
	}
	for _, trackingEntry := range bonusCandidate {
		ctxField := logrus.Fields{
			"invitee": trackingEntry.Invitee,
			"invitor": trackingEntry.Invitor,
			"plan":    trackingEntry.PlanType,
			"action":  "upgrade_bonus",
		}
		logger.WithFields(ctxField).Info("processing referral upgrade")
		upgradeErr := c.StorageBonus.TrackUpgradeAndInvitorBonus(ctx, trackingEntry.Invitee, trackingEntry.Invitor, trackingEntry.PlanType)
		if upgradeErr != nil {
			logger.WithError(upgradeErr).WithFields(ctxField).Error("failed to track upgrade and invitor bonusCandidate")
		} else {
			c.EmailNotificationController.OnSuccessfulReferral(trackingEntry.Invitor)
		}
	}

	bonusPenaltyCandidates, err := c.StorageBonus.GetReferredForDowngradePenalty(ctx)
	if err != nil {
		logger.WithError(err).Error("failed to GetReferredForUpgradeBonus")
		return
	}
	if len(bonusPenaltyCandidates) > 0 {
		// todo: implement downgrade penalty
		logger.WithField("count", len(bonusPenaltyCandidates)).Warn("candidates found for downgrade penalty")
	}
}
