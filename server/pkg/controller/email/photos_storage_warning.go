package email

import (
	"context"
	"fmt"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/email"
	"github.com/ente/museum/pkg/utils/time"
	log "github.com/sirupsen/logrus"
)

var sendPhotosStorageWarningEmail = email.SendTemplatedEmailV2

type photosStorageState struct {
	User             ente.User
	Usage, Allowance int64
}

func (c *EmailNotificationController) SendPhotosStorageWarningMails() {
	if c.UserRepo.IsLikelySelfHosted() {
		return
	}
	const lockID = "photos_storage_warning_mail_lock"
	if !c.LockController.TryLock(lockID, time.MicrosecondsAfterHours(24)) {
		return
	}
	defer c.LockController.ReleaseLock(lockID)
	ctx := context.Background()
	ids, err := c.UserRepo.GetPhotosStorageWarningCandidates(ctx)
	if err != nil {
		log.WithError(err).Error("Failed to fetch Photos storage email candidates")
		return
	}
	for _, id := range ids {
		state, event, err := c.preparePhotosStorageEmail(ctx, id)
		logger := log.WithField("user_id", id)
		if err != nil {
			logger.WithError(err).Error("Failed to prepare Photos storage email")
			continue
		}
		if event == "" {
			continue
		}
		subject, name := "Your Ente Photos storage is almost full", "photos_storage_warning.html"
		if event == repo.PhotosStorageReminderTemplateID {
			name = "photos_storage_reminder.html"
		}
		full := state.Usage >= state.Allowance
		if full {
			subject = "Your Ente Photos storage is full"
		}
		err = sendPhotosStorageWarningEmail([]string{state.User.Email}, "Ente", "team@ente.com", subject, "ente_base.html", name,
			map[string]interface{}{"Full": full, "UsagePercent": photosStorageUsagePercent(state.Usage, state.Allowance)}, nil)
		if err != nil {
			logger.WithError(err).WithField("event", event).Error("Failed to send Photos storage email")
			continue
		}
	}
}

func (c *EmailNotificationController) preparePhotosStorageEmail(ctx context.Context, userID int64) (photosStorageState, string, error) {
	var state photosStorageState
	history, err := c.NotificationHistoryRepo.GetLastNotificationTimes(userID, []string{
		repo.PhotosStorageWarningTemplateID, repo.PhotosStorageReminderTemplateID, repo.StorageLimitExceededTemplateID,
		repo.StorageWarningExpiredScheduledDeletionTemplateID, repo.StorageWarningActiveOverageScheduledDeletionTemplateID,
		repo.StorageWarningLoginGraceTemplateID,
	})
	if err != nil {
		return state, "", err
	}
	if history[repo.PhotosStorageReminderTemplateID] > 0 || history[repo.StorageLimitExceededTemplateID] > 0 {
		return state, "", nil
	}
	now := time.Microseconds()
	blocked := history[repo.StorageWarningExpiredScheduledDeletionTemplateID] > 0 || history[repo.StorageWarningActiveOverageScheduledDeletionTemplateID] > 0 || history[repo.StorageWarningLoginGraceTemplateID] > 0
	if blocked && !repo.StorageWarningLoginGraceActive(history[repo.StorageWarningLoginGraceTemplateID], now) {
		return state, "", nil
	}
	event := repo.PhotosStorageWarningTemplateID
	if first := history[repo.PhotosStorageWarningTemplateID]; first > 0 {
		if now-first < 48*time.MicroSecondsInOneHour {
			return state, "", nil
		}
		event = repo.PhotosStorageReminderTemplateID
	}
	state.User, err = c.UserRepo.Get(userID)
	if err != nil {
		return state, "", err
	}
	if state.User.Email == "" || state.User.FamilyAdminID != nil {
		return state, "", nil
	}
	subscription, err := c.BillingRepo.GetUserSubscription(userID)
	if err != nil {
		return state, "", err
	}
	if subscription.ProductID != ente.FreePlanProductID || subscription.ExpiryTime <= now {
		return state, "", nil
	}
	bonuses, err := c.StorageBonusRepo.GetActiveStorageBonuses(ctx, userID)
	if err != nil {
		return state, "", err
	}
	if bonuses.GetAddonStorage() > 0 {
		return state, "", nil
	}
	totalUsage, err := c.UsageRepo.GetUsage(userID)
	if err != nil {
		return state, "", err
	}
	lockerUsage, err := c.UsageRepo.GetLockerStorageUsage(ctx, []int64{userID})
	if err != nil {
		return state, "", err
	}
	state.Usage = totalUsage - lockerUsage.TotalUsage
	state.Allowance = subscription.Storage + bonuses.GetUsableBonus(subscription.Storage)
	if state.Allowance <= 0 || state.Usage < state.Allowance-state.Allowance/10 {
		return state, "", nil
	}
	claimed, err := c.NotificationHistoryRepo.ClaimPhotosStorageNotification(ctx, userID, event)
	if err != nil || !claimed {
		return state, "", err
	}
	return state, event, nil
}

func photosStorageUsagePercent(usage, allowance int64) string {
	tenths := usage * 1000 / allowance
	return fmt.Sprintf("%d.%d", tenths/10, tenths%10)
}
