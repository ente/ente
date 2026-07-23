package user

import (
	"context"
	"errors"
	"fmt"
	"runtime/debug"
	"strings"
	"sync"
	stdtime "time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller/discord"
	"github.com/ente/museum/pkg/controller/lock"
	"github.com/ente/museum/pkg/repo"
	emergencyRepo "github.com/ente/museum/pkg/repo/emergency"
	emailUtil "github.com/ente/museum/pkg/utils/email"
	"github.com/ente/museum/pkg/utils/time"
	log "github.com/sirupsen/logrus"
)

const (
	InactiveUserDeletionJobLock = "inactive_user_deletion_mail_lock"

	inactiveUserDeletionBatchSize    = 500
	inactiveUserWorkerCount          = 6
	inactiveUserEmailInFlightLimit   = 4
	inactiveUserDeletionFromName     = "Ente"
	inactiveUserDeletionFromEmail    = "team@ente.com"
	inactiveUserDeletionBaseTemplate = "ente_base.html"

	InactiveUserDeletionWarn2mTemplateID = "inactive_user_deletion_warn_2m_v2"
	InactiveUserDeletionWarn1mTemplateID = "inactive_user_deletion_warn_1m_v2"
	InactiveUserDeletionWarn7dTemplateID = "inactive_user_deletion_warn_7d_v2"
	InactiveUserDeletionWarn1dTemplateID = "inactive_user_deletion_warn_1d_v2"
	InactiveUserDeletionFinalTemplateID  = "inactive_user_deletion_confirm_13m_v2"

	inactiveUserDeletionWarn2mTemplate = "inactive-user-deletion/warn_2m.html"
	inactiveUserDeletionWarn1mTemplate = "inactive-user-deletion/warn_1m.html"
	inactiveUserDeletionWarn7dTemplate = "inactive-user-deletion/warn_7d.html"
	inactiveUserDeletionWarn1dTemplate = "inactive-user-deletion/warn_1d.html"
	inactiveUserDeletionFinalTemplate  = "inactive-user-deletion/confirm_13m.html"

	inactiveUserDeletionWarn2mSubject = "Action needed: Keep your Ente account active"
	inactiveUserDeletionWarn1mSubject = "Reminder: Sign in within 30 days to keep your Ente account"
	inactiveUserDeletionWarn7dSubject = "7-day reminder: Your Ente account is scheduled for deletion"
	inactiveUserDeletionWarn1dSubject = "Final reminder: Your Ente account will be deleted tomorrow"
	inactiveUserDeletionFinalSubject  = "Your Ente account has been deleted due to inactivity"
)

const (
	inactiveUserOneDayInMicroSeconds = 24 * time.MicroSecondsInOneHour

	// 13 months is modeled as 395 days (365 + 30). The first warning (2 months
	// before deletion) starts at 335 days of inactivity.
	inactiveUserThirteenMonthsInMicroSeconds = (365 + 30) * inactiveUserOneDayInMicroSeconds
	inactiveUserWarn2MonthsInMicroSeconds    = inactiveUserThirteenMonthsInMicroSeconds - (60 * inactiveUserOneDayInMicroSeconds)

	// Stage progression is based on when the previous stage email was sent.
	inactiveUserGap2mTo1m    = 30 * inactiveUserOneDayInMicroSeconds
	inactiveUserGap1mTo7d    = 23 * inactiveUserOneDayInMicroSeconds
	inactiveUserGap7dTo1d    = 6 * inactiveUserOneDayInMicroSeconds
	inactiveUserGap1dToFinal = inactiveUserOneDayInMicroSeconds
)

var inactiveUserDeletionTemplateIDs = []string{
	InactiveUserDeletionWarn2mTemplateID,
	InactiveUserDeletionWarn1mTemplateID,
	InactiveUserDeletionWarn7dTemplateID,
	InactiveUserDeletionWarn1dTemplateID,
	InactiveUserDeletionFinalTemplateID,
}

type inactivityEmailStage string

const (
	inactivityEmailStageNone   inactivityEmailStage = ""
	inactivityEmailStageWarn2m inactivityEmailStage = "warn_2m"
	inactivityEmailStageWarn1m inactivityEmailStage = "warn_1m"
	inactivityEmailStageWarn7d inactivityEmailStage = "warn_7d"
	inactivityEmailStageWarn1d inactivityEmailStage = "warn_1d"
	inactivityEmailStageFinal  inactivityEmailStage = "confirm_13m"
)

var inactivityEmailStageOrder = []inactivityEmailStage{
	inactivityEmailStageWarn2m,
	inactivityEmailStageWarn1m,
	inactivityEmailStageWarn7d,
	inactivityEmailStageWarn1d,
	inactivityEmailStageFinal,
}

type inactivityEmailStageConfig struct {
	TemplateID   string
	TemplateName string
	Subject      string
	IsFinal      bool
}

type inactiveUserRunStats struct {
	ProcessedUsers      int
	SentEmails          int
	SuccessByStage      map[inactivityEmailStage]int
	FailureByStage      map[inactivityEmailStage]int
	PreStageFailures    int
	PausedLegacyContact int
}

type inactiveCandidateResult struct {
	UserID              int64
	Stage               inactivityEmailStage
	Sent                bool
	PausedLegacyContact bool
	Err                 error
}

func newInactiveUserRunStats() inactiveUserRunStats {
	successByStage := make(map[inactivityEmailStage]int, len(inactivityEmailStageOrder))
	failureByStage := make(map[inactivityEmailStage]int, len(inactivityEmailStageOrder))
	for _, stage := range inactivityEmailStageOrder {
		successByStage[stage] = 0
		failureByStage[stage] = 0
	}
	return inactiveUserRunStats{
		SuccessByStage: successByStage,
		FailureByStage: failureByStage,
	}
}

func hasAnyStageSuccess(successByStage map[inactivityEmailStage]int) bool {
	for _, stage := range inactivityEmailStageOrder {
		if successByStage[stage] > 0 {
			return true
		}
	}
	return false
}

func hasInactiveUserRunSummaryActivity(stats inactiveUserRunStats) bool {
	return hasAnyStageSuccess(stats.SuccessByStage) || stats.PausedLegacyContact > 0
}

func formatNonZeroStageCounts(counts map[inactivityEmailStage]int) string {
	parts := make([]string, 0, len(inactivityEmailStageOrder))
	for _, stage := range inactivityEmailStageOrder {
		if counts[stage] > 0 {
			parts = append(parts, fmt.Sprintf("%s=%d", stage, counts[stage]))
		}
	}
	if len(parts) == 0 {
		return ""
	}
	return fmt.Sprintf("{%s}", strings.Join(parts, ", "))
}

func buildInactiveUserRunSummary(stats inactiveUserRunStats, runAt int64) string {
	parts := make([]string, 0, 6)
	if stats.ProcessedUsers > 0 {
		parts = append(parts, fmt.Sprintf("processed=%d", stats.ProcessedUsers))
	}
	if stats.SentEmails > 0 {
		parts = append(parts, fmt.Sprintf("sent=%d", stats.SentEmails))
	}
	if success := formatNonZeroStageCounts(stats.SuccessByStage); success != "" {
		parts = append(parts, fmt.Sprintf("success=%s", success))
	}
	if failures := formatNonZeroStageCounts(stats.FailureByStage); failures != "" {
		parts = append(parts, fmt.Sprintf("failures=%s", failures))
	}
	if stats.PreStageFailures > 0 {
		parts = append(parts, fmt.Sprintf("pre_stage_failures=%d", stats.PreStageFailures))
	}
	if stats.PausedLegacyContact > 0 {
		parts = append(parts, fmt.Sprintf("paused_legacy_contact=%d", stats.PausedLegacyContact))
	}

	summary := fmt.Sprintf("Inactive user run summary (%s)", stdtime.UnixMicro(runAt).UTC().Format(stdtime.RFC3339))
	if len(parts) == 0 {
		return summary
	}
	return fmt.Sprintf("%s: %s", summary, strings.Join(parts, " | "))
}

// InactiveUserOrchestrator sends inactivity warning emails and final account
// deletion notifications for users who stay inactive across all apps.
type InactiveUserOrchestrator struct {
	UserRepo                *repo.UserRepository
	NotificationHistoryRepo *repo.NotificationHistoryRepository
	EmergencyContactRepo    *emergencyRepo.Repository
	LockController          *lock.LockController
	DiscordController       *discord.DiscordController
	UserController          *UserController
}

func NewInactiveUserOrchestrator(
	userRepo *repo.UserRepository,
	notificationHistoryRepo *repo.NotificationHistoryRepository,
	emergencyContactRepo *emergencyRepo.Repository,
	lockController *lock.LockController,
	discordController *discord.DiscordController,
	userController *UserController,
) *InactiveUserOrchestrator {
	return &InactiveUserOrchestrator{
		UserRepo:                userRepo,
		NotificationHistoryRepo: notificationHistoryRepo,
		EmergencyContactRepo:    emergencyContactRepo,
		LockController:          lockController,
		DiscordController:       discordController,
		UserController:          userController,
	}
}

func (c *InactiveUserOrchestrator) ProcessInactiveUsers() {
	lockUntil := time.MicrosecondsAfterHours(24)
	if !c.LockController.TryLock(InactiveUserDeletionJobLock, lockUntil) {
		log.Info("Skipping inactive user processing because another instance is running")
		return
	}
	defer c.LockController.ReleaseLock(InactiveUserDeletionJobLock)

	now := time.Microseconds()
	beforeTime := now - inactiveUserWarn2MonthsInMicroSeconds
	var afterUserID int64
	stats := newInactiveUserRunStats()
	emailSemaphore := make(chan struct{}, inactiveUserEmailInFlightLimit)

	for {
		candidates, err := c.UserRepo.GetActiveUsersByLastActivityBefore(beforeTime, afterUserID, inactiveUserDeletionBatchSize)
		if err != nil {
			log.WithError(err).Error("Failed to fetch inactive users")
			return
		}
		if len(candidates) == 0 {
			break
		}

		afterUserID = candidates[len(candidates)-1].UserID
		results := c.processCandidateBatch(candidates, now, emailSemaphore)
		for _, result := range results {
			stats.ProcessedUsers++
			if result.Err != nil {
				if result.Stage == inactivityEmailStageNone {
					stats.PreStageFailures++
				} else {
					stats.FailureByStage[result.Stage]++
				}
				log.WithError(result.Err).WithField("user_id", result.UserID).Error("Failed to process inactive user candidate")
				continue
			}
			if result.PausedLegacyContact {
				stats.PausedLegacyContact++
			}
			if result.Sent {
				stats.SentEmails++
				stats.SuccessByStage[result.Stage]++
			}
		}
	}

	log.WithFields(log.Fields{
		"processed_users":       stats.ProcessedUsers,
		"sent_emails":           stats.SentEmails,
		"stage_success":         stats.SuccessByStage,
		"stage_failures":        stats.FailureByStage,
		"pre_stage_failures":    stats.PreStageFailures,
		"paused_legacy_contact": stats.PausedLegacyContact,
		"has_stage_movements":   hasAnyStageSuccess(stats.SuccessByStage),
		"has_summary_activity":  hasInactiveUserRunSummaryActivity(stats),
	}).Info("Completed inactive user processing")

	if c.DiscordController != nil && hasInactiveUserRunSummaryActivity(stats) {
		c.DiscordController.NotifyAdminAction(buildInactiveUserRunSummary(stats, now))
	}
}

func (c *InactiveUserOrchestrator) processCandidateBatch(candidates []repo.UserInactivityCandidate, now int64, emailSemaphore chan struct{}) []inactiveCandidateResult {
	if len(candidates) == 0 {
		return nil
	}

	workerCount := min(len(candidates), inactiveUserWorkerCount)

	candidateCh := make(chan repo.UserInactivityCandidate, len(candidates))
	resultCh := make(chan inactiveCandidateResult, len(candidates))
	var wg sync.WaitGroup

	for range workerCount {
		wg.Go(func() {
			for candidate := range candidateCh {
				func(candidate repo.UserInactivityCandidate) {
					defer func() {
						if recovered := recover(); recovered != nil {
							log.WithFields(log.Fields{
								"user_id": candidate.UserID,
								"panic":   recovered,
								"stack":   string(debug.Stack()),
							}).Error("Recovered panic while processing inactive user candidate")
							resultCh <- inactiveCandidateResult{
								UserID: candidate.UserID,
								Stage:  inactivityEmailStageNone,
								Sent:   false,
								Err:    fmt.Errorf("panic while processing inactive user candidate: %v", recovered),
							}
						}
					}()

					stage, sent, pausedLegacyContact, err := c.processCandidate(candidate, now, emailSemaphore)
					resultCh <- inactiveCandidateResult{
						UserID:              candidate.UserID,
						Stage:               stage,
						Sent:                sent,
						PausedLegacyContact: pausedLegacyContact,
						Err:                 err,
					}
				}(candidate)
			}
		})
	}

	for _, candidate := range candidates {
		candidateCh <- candidate
	}
	close(candidateCh)

	wg.Wait()
	close(resultCh)

	results := make([]inactiveCandidateResult, 0, len(candidates))
	for result := range resultCh {
		results = append(results, result)
	}
	return results
}

func (c *InactiveUserOrchestrator) processCandidate(candidate repo.UserInactivityCandidate, now int64, emailSemaphore chan struct{}) (inactivityEmailStage, bool, bool, error) {
	stageHint, err := c.resolveNextStage(candidate.UserID, candidate.LastActivity, now)
	if err != nil {
		return inactivityEmailStageNone, false, false, err
	}
	if stageHint == inactivityEmailStageNone {
		return inactivityEmailStageNone, false, false, nil
	}

	user, err := c.UserRepo.Get(candidate.UserID)
	if err != nil {
		if errors.Is(err, ente.ErrUserDeleted) {
			return inactivityEmailStageNone, false, false, nil
		}
		return stageHint, false, false, err
	}

	hasActivePaidEntitlement, err := c.hasActivePaidEntitlement(user.ID)
	if err != nil {
		return stageHint, false, false, err
	}
	if hasActivePaidEntitlement {
		log.WithField("user_id", user.ID).Info("Skipping inactive user processing because user has active paid entitlement")
		return inactivityEmailStageNone, false, false, nil
	}

	lastActivity, found, err := c.UserRepo.GetLatestActivity(user.ID)
	if err != nil {
		return stageHint, false, false, err
	}
	if !found {
		// User is no longer active.
		return inactivityEmailStageNone, false, false, nil
	}

	stage := stageHint
	if lastActivity != candidate.LastActivity {
		stage, err = c.resolveNextStage(user.ID, lastActivity, now)
		if err != nil {
			return stageHint, false, false, err
		}
	}
	if stage == inactivityEmailStageNone {
		return inactivityEmailStageNone, false, false, nil
	}

	config := inactivityStageConfig(stage)
	if config.TemplateID == "" {
		return inactivityEmailStageNone, false, false, nil
	}

	accountRecoveryLink := ""
	if config.IsFinal {
		if c.UserController == nil {
			return stage, false, false, fmt.Errorf("inactive user deletion requires user controller")
		}
		hasActivePaidEntitlement, err := c.hasActivePaidEntitlement(user.ID)
		if err != nil {
			return stage, false, false, err
		}
		if hasActivePaidEntitlement {
			log.WithField("user_id", user.ID).Info("Skipping inactive user deletion because user has active paid entitlement")
			return inactivityEmailStageNone, false, false, nil
		}

		// Re-check right before deletion to avoid deleting users who became active
		// after earlier reads in long processing runs.
		latestActivity, latestFound, err := c.UserRepo.GetLatestActivity(user.ID)
		if err != nil {
			return stage, false, false, err
		}
		if !latestFound {
			return inactivityEmailStageNone, false, false, nil
		}
		latestStage, err := c.resolveNextStage(user.ID, latestActivity, now)
		if err != nil {
			return stage, false, false, err
		}
		if latestStage != inactivityEmailStageFinal {
			log.WithField("user_id", user.ID).Info("Skipping inactive user deletion because user is no longer in final stage")
			return inactivityEmailStageNone, false, false, nil
		}
		if c.EmergencyContactRepo != nil {
			hasActiveLegacyContact, err := c.EmergencyContactRepo.HasActiveLegacyContact(context.Background(), user.ID)
			if err != nil {
				return stage, false, false, err
			}
			if hasActiveLegacyContact {
				log.WithField("user_id", user.ID).Info("Skipping inactive user deletion because user has active legacy contact configured")
				return inactivityEmailStageNone, false, true, nil
			}
		}

		accountRecoveryLink, err = c.UserController.getAccountRecoveryLink(user.ID, user.Email)
		if err != nil {
			return stage, false, false, err
		}

		deleteLogger := log.WithFields(log.Fields{
			"user_id": user.ID,
			"req_ctx": "inactive_account_deletion",
		})
		if _, err := c.UserController.HandleAutomatedAccountDeletion(context.Background(), user.ID, deleteLogger); err != nil {
			return stage, false, false, err
		}
	}

	deletionDate := formatDeletionDateForStage(stage, now)
	templateData := map[string]interface{}{
		"Email":        user.Email,
		"DeletionDate": deletionDate,
	}
	if accountRecoveryLink != "" {
		templateData["AccountRecoveryLink"] = accountRecoveryLink
	}
	if emailSemaphore != nil {
		emailSemaphore <- struct{}{}
		defer func() {
			<-emailSemaphore
		}()
	}
	if err := emailUtil.SendTemplatedEmailV2(
		[]string{user.Email},
		inactiveUserDeletionFromName,
		inactiveUserDeletionFromEmail,
		config.Subject,
		inactiveUserDeletionBaseTemplate,
		config.TemplateName,
		templateData,
		nil,
	); err != nil {
		return stage, false, false, err
	}

	if err := c.NotificationHistoryRepo.SetLastNotificationTimeToNow(user.ID, config.TemplateID); err != nil {
		return stage, false, false, err
	}

	log.WithFields(log.Fields{
		"user_id":       user.ID,
		"email":         user.Email,
		"template_id":   config.TemplateID,
		"deletion_date": deletionDate,
	}).Info("Sent inactive user email")

	return stage, true, false, nil
}

func (c *InactiveUserOrchestrator) hasActivePaidEntitlement(userID int64) (bool, error) {
	err := c.UserController.BillingController.HasActiveSelfOrFamilySubscription(userID, true)
	if err == nil {
		return true, nil
	}
	if errors.Is(err, ente.ErrNoActiveSubscription) || errors.Is(err, ente.ErrSharingDisabledForFreeAccounts) {
		return false, nil
	}
	return false, err
}

func (c *InactiveUserOrchestrator) resolveNextStage(userID int64, lastActivity int64, now int64) (inactivityEmailStage, error) {
	history, err := c.NotificationHistoryRepo.GetLastNotificationTimes(userID, inactiveUserDeletionTemplateIDs)
	if err != nil {
		return inactivityEmailStageNone, err
	}
	return nextInactivityEmailStage(lastActivity, now, history), nil
}

func nextInactivityEmailStage(lastActivity int64, now int64, history map[string]int64) inactivityEmailStage {
	if now-lastActivity < inactiveUserWarn2MonthsInMicroSeconds {
		return inactivityEmailStageNone
	}

	sent2m := history[InactiveUserDeletionWarn2mTemplateID]
	if sent2m <= lastActivity {
		return inactivityEmailStageWarn2m
	}

	sentFinal := history[InactiveUserDeletionFinalTemplateID]
	if sentFinal > lastActivity {
		return inactivityEmailStageNone
	}

	sent1m := history[InactiveUserDeletionWarn1mTemplateID]
	if sent1m <= lastActivity {
		if now >= sent2m+inactiveUserGap2mTo1m {
			return inactivityEmailStageWarn1m
		}
		return inactivityEmailStageNone
	}

	sent7d := history[InactiveUserDeletionWarn7dTemplateID]
	if sent7d <= lastActivity {
		if now >= sent1m+inactiveUserGap1mTo7d {
			return inactivityEmailStageWarn7d
		}
		return inactivityEmailStageNone
	}

	sent1d := history[InactiveUserDeletionWarn1dTemplateID]
	if sent1d <= lastActivity {
		if now >= sent7d+inactiveUserGap7dTo1d {
			return inactivityEmailStageWarn1d
		}
		return inactivityEmailStageNone
	}

	if now >= sent1d+inactiveUserGap1dToFinal {
		return inactivityEmailStageFinal
	}
	return inactivityEmailStageNone
}

func inactivityStageConfig(stage inactivityEmailStage) inactivityEmailStageConfig {
	switch stage {
	case inactivityEmailStageWarn2m:
		return inactivityEmailStageConfig{
			TemplateID:   InactiveUserDeletionWarn2mTemplateID,
			TemplateName: inactiveUserDeletionWarn2mTemplate,
			Subject:      inactiveUserDeletionWarn2mSubject,
		}
	case inactivityEmailStageWarn1m:
		return inactivityEmailStageConfig{
			TemplateID:   InactiveUserDeletionWarn1mTemplateID,
			TemplateName: inactiveUserDeletionWarn1mTemplate,
			Subject:      inactiveUserDeletionWarn1mSubject,
		}
	case inactivityEmailStageWarn7d:
		return inactivityEmailStageConfig{
			TemplateID:   InactiveUserDeletionWarn7dTemplateID,
			TemplateName: inactiveUserDeletionWarn7dTemplate,
			Subject:      inactiveUserDeletionWarn7dSubject,
		}
	case inactivityEmailStageWarn1d:
		return inactivityEmailStageConfig{
			TemplateID:   InactiveUserDeletionWarn1dTemplateID,
			TemplateName: inactiveUserDeletionWarn1dTemplate,
			Subject:      inactiveUserDeletionWarn1dSubject,
		}
	case inactivityEmailStageFinal:
		return inactivityEmailStageConfig{
			TemplateID:   InactiveUserDeletionFinalTemplateID,
			TemplateName: inactiveUserDeletionFinalTemplate,
			Subject:      inactiveUserDeletionFinalSubject,
			IsFinal:      true,
		}
	default:
		return inactivityEmailStageConfig{}
	}
}

func formatDeletionDateForStage(stage inactivityEmailStage, now int64) string {
	var daysUntilDeletion int64
	switch stage {
	case inactivityEmailStageWarn2m:
		daysUntilDeletion = 60
	case inactivityEmailStageWarn1m:
		daysUntilDeletion = 30
	case inactivityEmailStageWarn7d:
		daysUntilDeletion = 7
	case inactivityEmailStageWarn1d:
		daysUntilDeletion = 1
	case inactivityEmailStageFinal:
		daysUntilDeletion = 0
	}
	deletionTime := stdtime.UnixMicro(now + daysUntilDeletion*inactiveUserOneDayInMicroSeconds).UTC()
	return deletionTime.Format("02 Jan 2006")
}
