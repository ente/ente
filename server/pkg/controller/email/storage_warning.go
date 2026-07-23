package email

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	stdtime "time"

	"github.com/ente/museum/ente"
	bonus "github.com/ente/museum/ente/storagebonus"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/billing"
	emailUtil "github.com/ente/museum/pkg/utils/email"
	"github.com/ente/museum/pkg/utils/rollout"
	"github.com/ente/museum/pkg/utils/time"
	log "github.com/sirupsen/logrus"
)

const (
	StorageWarningMailLock = "storage_warning_mail_lock"

	storageWarningBaseTemplate = "ente_base.html"
	storageWarningFromName     = "Ente"
	storageWarningFromEmail    = "support@ente.com"

	storageWarningOverageThreshold             = int64(25 * (1 << 30))
	storageWarningPreviousStageFreshnessWindow = 35 * 24 * time.MicroSecondsInOneHour
	storageWarningOneDayInMicroseconds         = 24 * time.MicroSecondsInOneHour
	storageWarningBufferedCadenceExtraGrace    = 2 * storageWarningOneDayInMicroseconds
	storageWarningRolloutPercentage            = 100
	storageWarningRolloutNonce                 = "storage-warning-v1"

	storageWarningActiveOverageNotificationGroup = "storage_warning_active_overage"
	storageWarningExpiredNotificationGroup       = "storage_warning_expired"
)

type storageWarningBucket string

const (
	storageWarningBucketNone          storageWarningBucket = "none"
	storageWarningBucketExpired       storageWarningBucket = "expired"
	storageWarningBucketActiveOverage storageWarningBucket = "active_over_25_gib"
)

type storageWarningSnapshot struct {
	RecipientID          int64
	AccountEmail         string
	TotalUsage           int64
	BaseStorage          int64
	UsableBonus          int64
	AllottedStorage      int64
	AvailableStorage     int64
	SubscriptionExpiry   int64
	EffectiveExpiry      int64
	ExpiredWarningAnchor int64
	EvaluatedAt          int64
	CurrentBucket        storageWarningBucket
	Bucket               storageWarningBucket
	ActiveOverageStage   activeOverageWarningStage
	ExpiredStage         expiredWarningStage
	ExpiredBufferedCycle bool
	AutoDeleteDate       int64
	IsFamilyPlan         bool
	WarningCycleStart    int64
	NotificationHistory  map[string]int64
}

type storageWarningMetrics struct {
	BaseStorage          int64
	UsableBonus          int64
	AllottedStorage      int64
	AvailableStorage     int64
	SubscriptionExpiry   int64
	EffectiveExpiry      int64
	ExpiredWarningAnchor int64
	Bucket               storageWarningBucket
}

type storageWarningRunStats struct {
	ProcessedUsers        int
	SentEmails            int
	SuccessByStage        map[string]int
	FailureByStage        map[string]int
	SkippedRolloutByStage map[string]int
	PreStageFailures      int
	SkippedRolloutPct     int
}

type storageWarningProcessResult string

const (
	storageWarningProcessResultSkipped        storageWarningProcessResult = "skipped"
	storageWarningProcessResultSkippedRollout storageWarningProcessResult = "skipped_rollout"
	storageWarningProcessResultSent           storageWarningProcessResult = "sent"
)

var sendStorageWarningTemplatedEmail = emailUtil.SendTemplatedEmailV2

var persistStorageWarningHistory = func(notificationHistoryRepo *repo.NotificationHistoryRepository, snapshot storageWarningSnapshot, templateID string) error {
	historyGroup := storageWarningHistoryGroup(snapshot)
	if historyGroup == "" {
		return notificationHistoryRepo.SetLastNotificationTimeToNow(snapshot.RecipientID, templateID)
	}
	return notificationHistoryRepo.SetLastNotificationTimeToNowWithGroup(snapshot.RecipientID, templateID, historyGroup)
}

// The login-grace marker is not a warning stage. It is fetched alongside stage
// history so the daily job can pause or resume terminal enforcement.
func storageWarningTemplateIDsWithLoginGrace(templateIDs []string) []string {
	result := make([]string, 0, len(templateIDs)+1)
	result = append(result, templateIDs...)
	result = append(result, repo.StorageWarningLoginGraceTemplateID)
	return result
}

var storageWarningStageOrder = []string{
	string(expiredWarningStage0),
	string(expiredWarningStage30),
	string(expiredWarningStage60),
	string(expiredWarningStage90),
	string(expiredWarningStage119),
	string(expiredWarningStageScheduledDeletion),
	string(activeOverageWarningStage0),
	string(activeOverageWarningStage30),
	string(activeOverageWarningStage60),
	string(activeOverageWarningStage89),
	string(activeOverageWarningStageScheduledDeletion),
}

func newStorageWarningRunStats() storageWarningRunStats {
	successByStage := make(map[string]int, len(storageWarningStageOrder))
	failureByStage := make(map[string]int, len(storageWarningStageOrder))
	skippedRolloutByStage := make(map[string]int, len(storageWarningStageOrder))
	for _, stage := range storageWarningStageOrder {
		successByStage[stage] = 0
		failureByStage[stage] = 0
		skippedRolloutByStage[stage] = 0
	}
	return storageWarningRunStats{
		SuccessByStage:        successByStage,
		FailureByStage:        failureByStage,
		SkippedRolloutByStage: skippedRolloutByStage,
	}
}

func hasAnyStorageWarningStageCount(counts map[string]int) bool {
	for _, stage := range storageWarningStageOrder {
		if counts[stage] > 0 {
			return true
		}
	}
	return false
}

func formatStorageWarningNonZeroStageCounts(counts map[string]int) string {
	parts := make([]string, 0, len(storageWarningStageOrder))
	for _, stage := range storageWarningStageOrder {
		if counts[stage] <= 0 {
			continue
		}
		parts = append(parts, fmt.Sprintf("%s=%d", stage, counts[stage]))
	}
	return strings.Join(parts, ", ")
}

func buildStorageWarningRunSummary(stats storageWarningRunStats, runAt int64) string {
	parts := []string{
		fmt.Sprintf("processed=%d", stats.ProcessedUsers),
		fmt.Sprintf("sent=%d", stats.SentEmails),
	}
	if hasAnyStorageWarningStageCount(stats.SuccessByStage) {
		parts = append(parts, fmt.Sprintf("success={%s}", formatStorageWarningNonZeroStageCounts(stats.SuccessByStage)))
	}
	if hasAnyStorageWarningStageCount(stats.FailureByStage) {
		parts = append(parts, fmt.Sprintf("failures={%s}", formatStorageWarningNonZeroStageCounts(stats.FailureByStage)))
	}
	if hasAnyStorageWarningStageCount(stats.SkippedRolloutByStage) {
		parts = append(parts, fmt.Sprintf("skipped_rollout={%s}", formatStorageWarningNonZeroStageCounts(stats.SkippedRolloutByStage)))
	}
	if stats.PreStageFailures > 0 {
		parts = append(parts, fmt.Sprintf("pre_stage_failures=%d", stats.PreStageFailures))
	}
	if stats.SkippedRolloutPct > 0 {
		parts = append(parts, fmt.Sprintf("skipped_rollout_percentage=%d", stats.SkippedRolloutPct))
	}
	parts = append(parts, fmt.Sprintf("rollout_percentage=%d", storageWarningRolloutPercentage))

	return fmt.Sprintf(
		"Storage warning run summary (%s): %s",
		stdtime.UnixMicro(runAt).UTC().Format(stdtime.RFC3339),
		strings.Join(parts, " | "),
	)
}

func (c *EmailNotificationController) SendStorageWarningMails() {
	if c.UserRepo == nil || c.UsageRepo == nil || c.BillingRepo == nil || c.StorageBonusRepo == nil ||
		c.LockController == nil || c.NotificationHistoryRepo == nil {
		log.Error("Skipping storage warning mails: controller dependencies are not fully configured")
		return
	}
	if c.UserRepo.IsLikelySelfHosted() {
		return
	}
	log.Info("Running storage warning mails for cloud instance")

	lockStatus := c.LockController.TryLock(StorageWarningMailLock, time.MicrosecondsAfterHours(24))
	if !lockStatus {
		log.Info("Skipping storage warning mails as another instance is still running")
		return
	}
	defer c.LockController.ReleaseLock(StorageWarningMailLock)

	ctx := context.Background()
	now := time.Microseconds()
	candidates, err := c.UsageRepo.GetStorageWarningCandidates(ctx, storageWarningOverageThreshold)
	if err != nil {
		log.WithError(err).Error("Failed to fetch storage warning candidates")
		return
	}
	graceCandidates, err := c.NotificationHistoryRepo.GetStorageWarningLoginGraceCandidates(ctx)
	if err != nil {
		log.WithError(err).Error("Failed to fetch storage warning login grace candidates")
		return
	}
	candidates = mergeStorageWarningCandidates(candidates, graceCandidates)

	processed := 0
	sent := 0
	skipped := 0
	failed := 0
	skippedRolloutPct := 0
	stats := newStorageWarningRunStats()
	sentByBucket := map[storageWarningBucket]int{
		storageWarningBucketExpired:       0,
		storageWarningBucketActiveOverage: 0,
	}
	failedByBucket := map[storageWarningBucket]int{
		storageWarningBucketExpired:       0,
		storageWarningBucketActiveOverage: 0,
	}
	preserveActiveOverageHistoryRecipientIDs := make(map[int64]struct{})

	for _, candidate := range candidates {
		processed++
		stats.ProcessedUsers++
		snapshot, err := c.buildStorageWarningSnapshot(ctx, candidate, now)
		if err != nil {
			failed++
			stats.PreStageFailures++
			preserveActiveOverageHistoryRecipientIDs[candidate.RecipientID] = struct{}{}
			candidateType := "individual"
			if candidate.IsFamilyPlan {
				candidateType = "family"
			}
			log.WithFields(log.Fields{
				"recipient_id":   candidate.RecipientID,
				"candidate_type": candidateType,
			}).WithError(err).Error("Failed to build storage warning snapshot")
			continue
		}
		if storageWarningShouldPreserveActiveOverageHistory(snapshot) {
			preserveActiveOverageHistoryRecipientIDs[snapshot.RecipientID] = struct{}{}
		}
		result, err := c.processStorageWarningSnapshot(ctx, snapshot)
		if err != nil {
			failed++
			stage := storageWarningStageKey(snapshot)
			if stage == "" {
				stats.PreStageFailures++
			} else {
				stats.FailureByStage[stage]++
			}
			failedByBucket[snapshot.Bucket]++
			continue
		}
		if result == storageWarningProcessResultSkipped {
			skipped++
			continue
		}
		if result == storageWarningProcessResultSkippedRollout {
			skipped++
			skippedRolloutPct++
			stats.SkippedRolloutPct++
			if stage := storageWarningStageKey(snapshot); stage != "" {
				stats.SkippedRolloutByStage[stage]++
			}
			continue
		}
		if result == storageWarningProcessResultSent {
			sent++
			stats.SentEmails++
			if stage := storageWarningStageKey(snapshot); stage != "" {
				stats.SuccessByStage[stage]++
			}
			sentByBucket[snapshot.Bucket]++
		}
	}

	if err := c.cleanupActiveOverageWarningHistory(preserveActiveOverageHistoryRecipientIDs); err != nil {
		log.WithError(err).Error("Failed to clean up active overage notification history")
	}

	log.WithFields(log.Fields{
		"processed":                  processed,
		"sent":                       sent,
		"skipped":                    skipped,
		"failed":                     failed,
		"sent_expired":               sentByBucket[storageWarningBucketExpired],
		"sent_active_overage":        sentByBucket[storageWarningBucketActiveOverage],
		"failed_expired":             failedByBucket[storageWarningBucketExpired],
		"failed_active_overage":      failedByBucket[storageWarningBucketActiveOverage],
		"stage_success":              stats.SuccessByStage,
		"stage_failures":             stats.FailureByStage,
		"stage_skipped_rollout":      stats.SkippedRolloutByStage,
		"pre_stage_failures":         stats.PreStageFailures,
		"skipped_rollout_percentage": skippedRolloutPct,
		"has_stage_movements":        hasAnyStorageWarningStageCount(stats.SuccessByStage),
		"rollout_percentage":         storageWarningRolloutPercentage,
		"rollout_nonce":              storageWarningRolloutNonce,
	}).Info("Storage warning mail run completed")

	if c.DiscordController != nil && (hasAnyStorageWarningStageCount(stats.SuccessByStage) || hasAnyStorageWarningStageCount(stats.SkippedRolloutByStage)) {
		c.DiscordController.NotifyAdminAction(buildStorageWarningRunSummary(stats, now))
	}
}

// Keep the old entrypoint while external schedulers are updated.
func (c *EmailNotificationController) SendFamilyStorageWarningMails() {
	c.SendStorageWarningMails()
}

func mergeStorageWarningCandidates(candidateSets ...[]repo.StorageWarningCandidate) []repo.StorageWarningCandidate {
	result := make([]repo.StorageWarningCandidate, 0)
	indices := make(map[int64]int)
	for _, candidates := range candidateSets {
		for _, candidate := range candidates {
			if index, ok := indices[candidate.RecipientID]; ok {
				result[index].IsFamilyPlan = result[index].IsFamilyPlan || candidate.IsFamilyPlan
				continue
			}
			indices[candidate.RecipientID] = len(result)
			result = append(result, candidate)
		}
	}
	return result
}

func (c *EmailNotificationController) cleanupActiveOverageWarningHistory(preserveRecipientIDs map[int64]struct{}) error {
	keepUserIDs := make([]int64, 0, len(preserveRecipientIDs))
	for userID := range preserveRecipientIDs {
		keepUserIDs = append(keepUserIDs, userID)
	}
	return c.NotificationHistoryRepo.DeleteNotificationHistoryByGroupExcludingUsers(storageWarningActiveOverageNotificationGroup, keepUserIDs)
}

func (c *EmailNotificationController) clearStorageWarningLoginGrace(userID int64, logger *log.Entry) error {
	if c.NotificationHistoryRepo == nil {
		return nil
	}
	if err := c.NotificationHistoryRepo.ClearStorageWarningLoginGrace(userID); err != nil {
		if logger != nil {
			logger.WithError(err).Error("Failed to clear storage warning login grace")
		}
		return err
	}
	if logger != nil {
		logger.Info("Cleared storage warning login grace")
	}
	return nil
}

func (c *EmailNotificationController) clearRecoveredStorageWarningLoginState(userID int64, logger *log.Entry) error {
	if c.NotificationHistoryRepo == nil {
		return nil
	}
	// A cron/admin race can recreate the terminal login-block row while the grace
	// marker is active. Once the user recovers, remove both rows so clearing grace
	// does not expose the stale block again.
	if err := c.NotificationHistoryRepo.ClearStorageWarningDeletionScheduled(userID); err != nil {
		if logger != nil {
			logger.WithError(err).Error("Failed to clear storage warning deletion state after recovery")
		}
		return err
	}
	return c.clearStorageWarningLoginGrace(userID, logger)
}

func (c *EmailNotificationController) buildStorageWarningSnapshot(ctx context.Context, candidate repo.StorageWarningCandidate, now int64) (storageWarningSnapshot, error) {
	if candidate.IsFamilyPlan {
		return c.buildFamilyStorageWarningSnapshot(ctx, candidate.RecipientID, now)
	}
	return c.buildIndividualStorageWarningSnapshot(ctx, candidate.RecipientID, now)
}

func (c *EmailNotificationController) buildFamilyStorageWarningSnapshot(ctx context.Context, adminID int64, now int64) (storageWarningSnapshot, error) {
	admin, err := c.UserRepo.Get(adminID)
	if err != nil {
		return storageWarningSnapshot{}, err
	}
	if admin.Email == "" {
		return storageWarningSnapshot{}, fmt.Errorf("admin email not available")
	}

	totalUsage, err := c.UsageRepo.StorageForFamilyAdmin(adminID)
	if err != nil {
		return storageWarningSnapshot{}, err
	}

	activeBonuses, err := c.StorageBonusRepo.GetActiveStorageBonuses(ctx, adminID)
	if err != nil {
		return storageWarningSnapshot{}, err
	}

	subscription, err := c.BillingRepo.GetUserSubscription(adminID)
	var sub *ente.Subscription
	if err == nil {
		sub = &subscription
	} else if !errors.Is(err, sql.ErrNoRows) {
		return storageWarningSnapshot{}, err
	}

	metrics := computeStorageWarningMetrics(sub, activeBonuses, totalUsage, now)
	snapshot := storageWarningSnapshot{
		RecipientID:          adminID,
		AccountEmail:         admin.Email,
		TotalUsage:           totalUsage,
		BaseStorage:          metrics.BaseStorage,
		UsableBonus:          metrics.UsableBonus,
		AllottedStorage:      metrics.AllottedStorage,
		AvailableStorage:     metrics.AvailableStorage,
		SubscriptionExpiry:   metrics.SubscriptionExpiry,
		EffectiveExpiry:      metrics.EffectiveExpiry,
		ExpiredWarningAnchor: metrics.ExpiredWarningAnchor,
		EvaluatedAt:          now,
		CurrentBucket:        metrics.Bucket,
		Bucket:               metrics.Bucket,
		IsFamilyPlan:         true,
	}
	return c.decorateStorageWarningSnapshot(snapshot, now)
}

func (c *EmailNotificationController) buildIndividualStorageWarningSnapshot(ctx context.Context, userID int64, now int64) (storageWarningSnapshot, error) {
	user, err := c.UserRepo.Get(userID)
	if err != nil {
		return storageWarningSnapshot{}, err
	}
	if user.Email == "" {
		return storageWarningSnapshot{}, fmt.Errorf("user email not available")
	}

	totalUsage, err := c.UsageRepo.GetUsage(userID)
	if err != nil {
		return storageWarningSnapshot{}, err
	}

	activeBonuses, err := c.StorageBonusRepo.GetActiveStorageBonuses(ctx, userID)
	if err != nil {
		return storageWarningSnapshot{}, err
	}

	subscription, err := c.BillingRepo.GetUserSubscription(userID)
	var sub *ente.Subscription
	if err == nil {
		sub = &subscription
	} else if !errors.Is(err, sql.ErrNoRows) {
		return storageWarningSnapshot{}, err
	}

	metrics := computeStorageWarningMetrics(sub, activeBonuses, totalUsage, now)
	snapshot := storageWarningSnapshot{
		RecipientID:          userID,
		AccountEmail:         user.Email,
		TotalUsage:           totalUsage,
		BaseStorage:          metrics.BaseStorage,
		UsableBonus:          metrics.UsableBonus,
		AllottedStorage:      metrics.AllottedStorage,
		AvailableStorage:     metrics.AvailableStorage,
		SubscriptionExpiry:   metrics.SubscriptionExpiry,
		EffectiveExpiry:      metrics.EffectiveExpiry,
		ExpiredWarningAnchor: metrics.ExpiredWarningAnchor,
		EvaluatedAt:          now,
		CurrentBucket:        metrics.Bucket,
		Bucket:               metrics.Bucket,
		IsFamilyPlan:         false,
	}
	return c.decorateStorageWarningSnapshot(snapshot, now)
}

func (c *EmailNotificationController) decorateStorageWarningSnapshot(snapshot storageWarningSnapshot, now int64) (storageWarningSnapshot, error) {
	switch snapshot.Bucket {
	case storageWarningBucketExpired:
		history, err := c.NotificationHistoryRepo.GetLastNotificationTimes(snapshot.RecipientID, storageWarningTemplateIDsWithLoginGrace(expiredWarningTemplateIDs()))
		if err != nil {
			return storageWarningSnapshot{}, err
		}
		snapshot.NotificationHistory = history
		expiredResolution := resolveExpiredWarning(snapshot.ExpiredWarningAnchor, now, history)
		snapshot.WarningCycleStart = expiredResolution.CycleStart
		snapshot.ExpiredStage = expiredResolution.Stage
		snapshot.ExpiredBufferedCycle = expiredResolution.BufferedCycle
		snapshot.AutoDeleteDate = expiredResolution.AutoDeleteDate
		if snapshot.ExpiredStage == expiredWarningStageNone {
			snapshot.Bucket = storageWarningBucketNone
			return snapshot, nil
		}
	case storageWarningBucketActiveOverage:
		history, err := c.NotificationHistoryRepo.GetLastNotificationTimes(snapshot.RecipientID, storageWarningTemplateIDsWithLoginGrace(activeOverageWarningTemplateIDs()))
		if err != nil {
			return storageWarningSnapshot{}, err
		}
		snapshot.NotificationHistory = history
		overageResolution := resolveActiveOverageWarning(now, history)
		snapshot.ActiveOverageStage = overageResolution.Stage
		snapshot.WarningCycleStart = overageResolution.CycleStart
		if snapshot.ActiveOverageStage == activeOverageWarningStageNone {
			snapshot.Bucket = storageWarningBucketNone
			return snapshot, nil
		}
		snapshot.AutoDeleteDate = activeOverageWarningAutoDeleteDate(snapshot.WarningCycleStart, snapshot.ActiveOverageStage, now)
	case storageWarningBucketNone:
		history, err := c.NotificationHistoryRepo.GetLastNotificationTimes(snapshot.RecipientID, []string{repo.StorageWarningLoginGraceTemplateID})
		if err != nil {
			return storageWarningSnapshot{}, err
		}
		snapshot.NotificationHistory = history
	}
	return snapshot, nil
}

func (c *EmailNotificationController) processStorageWarningSnapshot(ctx context.Context, snapshot storageWarningSnapshot) (storageWarningProcessResult, error) {
	logger := log.WithFields(log.Fields{
		"recipient_id":   snapshot.RecipientID,
		"is_family_plan": snapshot.IsFamilyPlan,
	})
	graceActive, graceExpired, graceUntil := storageWarningLoginGraceState(snapshot)
	currentBucket := storageWarningCurrentBucket(snapshot)
	if currentBucket == storageWarningBucketNone && snapshot.Bucket == storageWarningBucketNone {
		if graceActive || graceExpired {
			if err := c.clearRecoveredStorageWarningLoginState(snapshot.RecipientID, logger); err != nil {
				return storageWarningProcessResultSkipped, err
			}
		}
		return storageWarningProcessResultSkipped, nil
	}

	// A soft-unblock pauses the terminal state machine for the full grace
	// window. This must run before cadence checks because active-overage
	// reminder history may already have been cleaned after the original block.
	if graceActive {
		logger.WithFields(log.Fields{
			"bucket":            snapshot.Bucket,
			"active_stage":      snapshot.ActiveOverageStage,
			"expired_stage":     snapshot.ExpiredStage,
			"login_grace_until": graceUntil,
		}).Info("Skipping storage warning due to active login grace")
		return storageWarningProcessResultSkipped, nil
	}
	if graceExpired {
		if snapshot.Bucket == storageWarningBucketNone {
			snapshot.Bucket = currentBucket
		}
		snapshot = storageWarningForceScheduledDeletionAfterLoginGrace(snapshot)
	}
	if snapshot.Bucket == storageWarningBucketNone {
		return storageWarningProcessResultSkipped, nil
	}

	templateID, templateName, subject, ok := storageWarningTemplateDetails(snapshot)
	if !ok {
		logger.WithField("bucket", snapshot.Bucket).Warn("Skipping storage warning due to unknown bucket")
		return storageWarningProcessResultSkipped, nil
	}

	if storageWarningTemplateSentInCycle(snapshot.NotificationHistory, templateID, snapshot.WarningCycleStart) {
		if graceExpired {
			if err := c.clearStorageWarningLoginGrace(snapshot.RecipientID, logger); err != nil {
				return storageWarningProcessResultSkipped, err
			}
		}
		return storageWarningProcessResultSkipped, nil
	}
	shouldResetUserAccess := storageWarningShouldResetUserAccess(snapshot)
	if cadenceBroken, cadenceAlert := storageWarningCadenceBroken(snapshot); cadenceBroken {
		if shouldResetUserAccess && graceExpired {
			logger.WithFields(log.Fields{
				"bucket":              snapshot.Bucket,
				"active_stage":        snapshot.ActiveOverageStage,
				"expired_stage":       snapshot.ExpiredStage,
				"template_id":         templateID,
				"login_grace_until":   graceUntil,
				"warning_cycle_start": snapshot.WarningCycleStart,
			}).Info("Allowing storage warning scheduled deletion after login grace expiry")
		} else {
			logger.WithFields(log.Fields{
				"bucket":              snapshot.Bucket,
				"active_stage":        snapshot.ActiveOverageStage,
				"expired_stage":       snapshot.ExpiredStage,
				"warning_cycle_start": snapshot.WarningCycleStart,
			}).Warn("Skipping storage warning due to broken stage cadence")
			if c.DiscordController != nil {
				c.DiscordController.NotifyAdminAction(cadenceAlert)
			}
			return storageWarningProcessResultSkipped, nil
		}
	}

	templateData := map[string]interface{}{
		"TotalUsage":       snapshot.TotalUsage,
		"AllottedStorage":  snapshot.AllottedStorage,
		"AvailableStorage": snapshot.AvailableStorage,
		"AccountEmail":     snapshot.AccountEmail,
		"ExpiryDate":       formatDate(snapshot.SubscriptionExpiry),
		"AutoDeleteDate":   formatDate(snapshot.AutoDeleteDate),
		"IsFamilyPlan":     snapshot.IsFamilyPlan,
	}
	logger = logger.WithFields(log.Fields{
		"bucket":                        snapshot.Bucket,
		"account_email":                 snapshot.AccountEmail,
		"rollout_nonce":                 storageWarningRolloutNonce,
		"rollout_percentage":            storageWarningRolloutPercentage,
		"base_storage":                  snapshot.BaseStorage,
		"usable_bonus":                  snapshot.UsableBonus,
		"total_usage":                   snapshot.TotalUsage,
		"allotted_storage":              snapshot.AllottedStorage,
		"available_storage":             snapshot.AvailableStorage,
		"overage_threshold":             storageWarningOverageThreshold,
		"overage_trigger_limit":         snapshot.AllottedStorage + storageWarningOverageThreshold,
		"usage_above_allotted":          positiveDelta(snapshot.TotalUsage, snapshot.AllottedStorage),
		"usage_above_trigger_limit":     positiveDelta(snapshot.TotalUsage, snapshot.AllottedStorage+storageWarningOverageThreshold),
		"base_storage_gib":              formatStorageGiB(snapshot.BaseStorage),
		"usable_bonus_gib":              formatStorageGiB(snapshot.UsableBonus),
		"total_usage_gib":               formatStorageGiB(snapshot.TotalUsage),
		"allotted_storage_gib":          formatStorageGiB(snapshot.AllottedStorage),
		"available_storage_gib":         formatStorageGiB(snapshot.AvailableStorage),
		"overage_trigger_limit_gib":     formatStorageGiB(snapshot.AllottedStorage + storageWarningOverageThreshold),
		"usage_above_allotted_gib":      formatStorageGiB(positiveDelta(snapshot.TotalUsage, snapshot.AllottedStorage)),
		"usage_above_trigger_limit_gib": formatStorageGiB(positiveDelta(snapshot.TotalUsage, snapshot.AllottedStorage+storageWarningOverageThreshold)),
		"subscription_expiry":           snapshot.SubscriptionExpiry,
		"effective_expiry":              snapshot.EffectiveExpiry,
		"expired_warning_anchor":        snapshot.ExpiredWarningAnchor,
		"warning_cycle_start":           snapshot.WarningCycleStart,
		"active_stage":                  snapshot.ActiveOverageStage,
		"expired_stage":                 snapshot.ExpiredStage,
		"auto_delete_date":              snapshot.AutoDeleteDate,
		"subject":                       subject,
		"template_id":                   templateID,
		"template_filename":             templateName,
	})
	if !isInStorageWarningRollout(snapshot.RecipientID, snapshot.AccountEmail) {
		return storageWarningProcessResultSkippedRollout, nil
	}
	if shouldResetUserAccess && c.UserAccessResetter == nil {
		err := errors.New("storage warning user access resetter is not configured")
		logger.WithError(err).Error("Failed to restrict user access for storage scheduled deletion")
		return storageWarningProcessResultSkipped, err
	}

	err := sendStorageWarningTemplatedEmail(
		[]string{snapshot.AccountEmail},
		storageWarningFromName,
		storageWarningFromEmail,
		subject,
		storageWarningBaseTemplate,
		templateName,
		templateData,
		nil,
	)
	if err != nil {
		logger.WithError(err).Error("Failed to send storage warning email")
		return storageWarningProcessResultSkipped, err
	}

	if shouldResetUserAccess {
		// Intentionally do not enqueue data cleanup here yet. We will start
		// scheduling auto-deletion only after validating that this workflow is
		// consistently identifying the correct deletion candidates.
		if err := c.UserAccessResetter.ResetUserAccess(ctx, snapshot.RecipientID, logger); err != nil {
			logger.WithError(err).Error("Failed to restrict user access for storage scheduled deletion")
			return storageWarningProcessResultSkipped, err
		}
		logger.Info("Restricted user access for storage scheduled deletion")
	}

	err = persistStorageWarningHistory(c.NotificationHistoryRepo, snapshot, templateID)
	if err != nil {
		logger.WithError(err).Error("Failed to persist storage warning history")
		return storageWarningProcessResultSkipped, err
	}
	if graceExpired {
		if err := c.clearStorageWarningLoginGrace(snapshot.RecipientID, logger); err != nil {
			return storageWarningProcessResultSkipped, err
		}
	}

	logger.Info("Sent storage warning email")
	return storageWarningProcessResultSent, nil
}

func computeStorageWarningMetrics(subscription *ente.Subscription, activeBonuses *bonus.ActiveStorageBonus, totalUsage int64, now int64) storageWarningMetrics {
	baseEffectiveExpiry := int64(0)
	baseStorage := int64(0)
	subscriptionExpiry := int64(0)
	if subscription != nil {
		subscriptionExpiry = subscription.ExpiryTime
		baseEffectiveExpiry = effectiveSubscriptionExpiry(*subscription)
		if baseEffectiveExpiry > now {
			baseStorage = subscription.Storage
		}
	}

	effectiveExpiry := baseEffectiveExpiry
	if bonusExpiry := activeBonuses.GetMaxExpiry(); bonusExpiry > effectiveExpiry {
		effectiveExpiry = bonusExpiry
	}

	usableBonus := activeBonuses.GetUsableBonus(baseStorage)
	allottedStorage := baseStorage + usableBonus
	expiredWarningAnchor := expiredWarningAnchorFromSubscriptionExpiry(subscriptionExpiry)
	return storageWarningMetrics{
		BaseStorage:          baseStorage,
		UsableBonus:          usableBonus,
		AllottedStorage:      allottedStorage,
		AvailableStorage:     allottedStorage - totalUsage,
		SubscriptionExpiry:   subscriptionExpiry,
		EffectiveExpiry:      effectiveExpiry,
		ExpiredWarningAnchor: expiredWarningAnchor,
		Bucket:               bucketStorageWarning(totalUsage, allottedStorage, effectiveExpiry, expiredWarningAnchor, now),
	}
}

func effectiveSubscriptionExpiry(subscription ente.Subscription) int64 {
	expiry := subscription.ExpiryTime
	if value, ok := billing.ProviderToExpiryGracePeriodMap[subscription.PaymentProvider]; ok {
		expiry += value
	}
	return expiry
}

func bucketStorageWarning(totalUsage int64, allottedStorage int64, effectiveExpiry int64, expiredWarningAnchor int64, now int64) storageWarningBucket {
	if totalUsage <= allottedStorage+storageWarningOverageThreshold {
		return storageWarningBucketNone
	}
	if effectiveExpiry > now && totalUsage > (allottedStorage+storageWarningOverageThreshold) {
		return storageWarningBucketActiveOverage
	}
	if expiredWarningAnchor > 0 && expiredWarningAnchor <= now {
		return storageWarningBucketExpired
	}
	return storageWarningBucketNone
}

func storageWarningTemplateDetails(snapshot storageWarningSnapshot) (templateID string, templateName string, subject string, ok bool) {
	switch snapshot.Bucket {
	case storageWarningBucketActiveOverage:
		return activeOverageWarningTemplateDetails(snapshot.ActiveOverageStage)
	case storageWarningBucketExpired:
		return expiredWarningTemplateDetails(snapshot.ExpiredStage)
	default:
		return "", "", "", false
	}
}

func formatDate(microseconds int64) string {
	if microseconds <= 0 {
		return ""
	}
	return stdtime.UnixMicro(microseconds).UTC().Format("January 2, 2006")
}

func formatTimestamp(microseconds int64) string {
	if microseconds <= 0 {
		return "missing"
	}
	return stdtime.UnixMicro(microseconds).UTC().Format(stdtime.RFC3339)
}

func buildStorageWarningCadenceAlert(snapshot storageWarningSnapshot, previousStageKey string, previousSentAt int64) string {
	return fmt.Sprintf(
		"Storage warning cadence broken: recipient_id=%d bucket=%s intended_stage=%s previous_required_stage=%s previous_sent_time=%s total_usage=%d allotted_storage=%d effective_expiry=%s",
		snapshot.RecipientID,
		snapshot.Bucket,
		storageWarningStageKey(snapshot),
		previousStageKey,
		formatTimestamp(previousSentAt),
		snapshot.TotalUsage,
		snapshot.AllottedStorage,
		formatTimestamp(snapshot.EffectiveExpiry),
	)
}

func storageWarningNotificationGroup(bucket storageWarningBucket) string {
	switch bucket {
	case storageWarningBucketActiveOverage:
		return storageWarningActiveOverageNotificationGroup
	case storageWarningBucketExpired:
		return storageWarningExpiredNotificationGroup
	default:
		return ""
	}
}

func storageWarningHistoryGroup(snapshot storageWarningSnapshot) string {
	// Terminal rows are deliberately ungrouped because they are the login-block
	// marker. Group cleanup only applies to reminder history.
	if storageWarningShouldResetUserAccess(snapshot) {
		return ""
	}
	return storageWarningNotificationGroup(snapshot.Bucket)
}

func storageWarningShouldResetUserAccess(snapshot storageWarningSnapshot) bool {
	switch snapshot.Bucket {
	case storageWarningBucketExpired:
		return snapshot.ExpiredStage == expiredWarningStageScheduledDeletion
	case storageWarningBucketActiveOverage:
		return snapshot.ActiveOverageStage == activeOverageWarningStageScheduledDeletion
	default:
		return false
	}
}

func storageWarningCurrentBucket(snapshot storageWarningSnapshot) storageWarningBucket {
	if snapshot.CurrentBucket != "" {
		return snapshot.CurrentBucket
	}
	return snapshot.Bucket
}

// storageWarningLoginGraceState evaluates the latest soft-unblock row. The
// daily job clears the row after recovery or re-block, so the timestamp itself
// defines the current window.
func storageWarningLoginGraceState(snapshot storageWarningSnapshot) (active bool, expired bool, graceUntil int64) {
	graceSentAt := snapshot.NotificationHistory[repo.StorageWarningLoginGraceTemplateID]
	if graceSentAt <= 0 {
		return false, false, 0
	}
	graceUntil = repo.StorageWarningLoginGraceUntil(graceSentAt)
	if repo.StorageWarningLoginGraceActive(graceSentAt, snapshot.EvaluatedAt) {
		return true, false, graceUntil
	}
	return false, true, graceUntil
}

func storageWarningForceScheduledDeletionAfterLoginGrace(snapshot storageWarningSnapshot) storageWarningSnapshot {
	switch snapshot.Bucket {
	case storageWarningBucketExpired:
		snapshot.ExpiredStage = expiredWarningStageScheduledDeletion
	case storageWarningBucketActiveOverage:
		snapshot.ActiveOverageStage = activeOverageWarningStageScheduledDeletion
	}
	if snapshot.WarningCycleStart <= 0 {
		snapshot.WarningCycleStart = snapshot.EvaluatedAt
	}
	if snapshot.AutoDeleteDate <= 0 {
		snapshot.AutoDeleteDate = snapshot.EvaluatedAt
	}
	return snapshot
}

func storageWarningShouldPreserveActiveOverageHistory(snapshot storageWarningSnapshot) bool {
	// Active-overage reminder rows are kept while the user is in a non-terminal
	// cycle. Once a terminal row exists, the row itself is enough to block login
	// and grouped reminder history may be cleaned.
	if snapshot.CurrentBucket != storageWarningBucketActiveOverage {
		return false
	}
	return !storageWarningTemplateSentInCycle(
		snapshot.NotificationHistory,
		repo.StorageWarningActiveOverageScheduledDeletionTemplateID,
		snapshot.WarningCycleStart,
	)
}

func storageWarningTemplateSentInCycle(history map[string]int64, templateID string, cycleStart int64) bool {
	if len(history) == 0 {
		return false
	}
	sentAt := history[templateID]
	if sentAt <= 0 {
		return false
	}
	if cycleStart <= 0 {
		return true
	}
	return sentAt >= cycleStart
}

func storageWarningStageKey(snapshot storageWarningSnapshot) string {
	switch snapshot.Bucket {
	case storageWarningBucketExpired:
		if snapshot.ExpiredStage == expiredWarningStageNone {
			return ""
		}
		return string(snapshot.ExpiredStage)
	case storageWarningBucketActiveOverage:
		if snapshot.ActiveOverageStage == activeOverageWarningStageNone {
			return ""
		}
		return string(snapshot.ActiveOverageStage)
	default:
		return ""
	}
}

func isEnteDomainStorageWarningAccount(email string) bool {
	normalizedEmail := emailUtil.NormalizeEmail(email)
	return strings.HasSuffix(normalizedEmail, "@ente.io") ||
		strings.HasSuffix(normalizedEmail, "@ente.com")
}

func isInStorageWarningRollout(userID int64, email string) bool {
	if isEnteDomainStorageWarningAccount(email) {
		return true
	}
	return rollout.IsInPercentageRollout(userID, storageWarningRolloutNonce, storageWarningRolloutPercentage)
}

func positiveDelta(lhs int64, rhs int64) int64 {
	if lhs <= rhs {
		return 0
	}
	return lhs - rhs
}

func formatStorageGiB(bytes int64) string {
	return fmt.Sprintf("%.2fGiB", float64(bytes)/float64(1<<30))
}
