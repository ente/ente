package controller

import (
	"context"
	"fmt"
	"strings"

	lockctrl "github.com/ente/museum/pkg/controller/lock"
	baserepo "github.com/ente/museum/pkg/repo"
	emailutil "github.com/ente/museum/pkg/utils/email"
	timeutil "github.com/ente/museum/pkg/utils/time"
	spacerepo "github.com/ente/museum/space/repo"
	log "github.com/sirupsen/logrus"
)

const (
	SpaceDripProfileMissing24hTemplateID = "space_profile_missing_24h"
	SpaceDripProfileMissing4dTemplateID  = "space_profile_missing_4d"
	SpaceDripInvitePeople24hTemplateID   = "space_invite_people_24h"
	SpaceDripInvitePeople4dTemplateID    = "space_invite_people_4d"
	SpaceDripFirstPost24hTemplateID      = "space_first_post_24h"
	SpaceDripFirstPost4dTemplateID       = "space_first_post_4d"
	SpaceDripFeedback7dTemplateID        = "space_feedback_7d"

	spaceDripTemplate         = "space_drip.html"
	spaceDripMailLock         = "space_drip_mail_lock"
	spaceDripDefaultBatchSize = 500
)

var sendSpaceDripEmail = emailutil.SendTemplatedEmail

type SpaceDripController struct {
	DripsRepo               *spacerepo.DripsRepository
	UserRepo                *baserepo.UserRepository
	NotificationHistoryRepo *baserepo.NotificationHistoryRepository
	LockController          *lockctrl.LockController
	BatchSize               int
}

type spaceDripStage struct {
	TemplateID string
	Subject    string
	BodyLines  []string
	CTALabel   string
	Candidates func(context.Context, int64, int) ([]spacerepo.SpaceDripCandidate, error)
}

type spaceDripRunStats struct {
	SentByTemplate map[string]int
}

func NewSpaceDripController(repos *spacerepo.Module, userRepo *baserepo.UserRepository, notificationHistoryRepo *baserepo.NotificationHistoryRepository, lockController *lockctrl.LockController) *SpaceDripController {
	return &SpaceDripController{
		DripsRepo:               repos.Drips,
		UserRepo:                userRepo,
		NotificationHistoryRepo: notificationHistoryRepo,
		LockController:          lockController,
	}
}

func (c *SpaceDripController) ProcessSpaceDrips() {
	if c == nil || c.DripsRepo == nil || c.UserRepo == nil || c.NotificationHistoryRepo == nil {
		log.Error("Skipping space drip emails because dependencies are missing")
		return
	}
	if c.LockController != nil {
		if !c.LockController.TryLock(spaceDripMailLock, timeutil.MicrosecondsAfterHours(24)) {
			log.Info("Skipping space drip emails because another instance is running")
			return
		}
		defer c.LockController.ReleaseLock(spaceDripMailLock)
	}
	stats, err := c.processSpaceDrips(context.Background(), timeutil.Microseconds())
	if err != nil {
		log.WithError(err).Error("Failed to process space drip emails")
		return
	}
	log.WithField("sent_by_template", stats.SentByTemplate).Info("Processed space drip emails")
}

func (c *SpaceDripController) processSpaceDrips(ctx context.Context, now int64) (spaceDripRunStats, error) {
	stats := spaceDripRunStats{SentByTemplate: map[string]int{}}
	handledThisRun := map[int64]struct{}{}
	batchSize := c.BatchSize
	if batchSize <= 0 {
		batchSize = spaceDripDefaultBatchSize
	}
	for _, stage := range c.spaceDripStages() {
		sent, err := c.processSpaceDripStage(ctx, stage, now, batchSize, handledThisRun)
		if err != nil {
			return stats, err
		}
		if sent > 0 {
			stats.SentByTemplate[stage.TemplateID] = sent
		}
	}
	return stats, nil
}

func (c *SpaceDripController) spaceDripStages() []spaceDripStage {
	day := int64(24) * timeutil.MicroSecondsInOneHour
	return []spaceDripStage{
		{
			TemplateID: SpaceDripProfileMissing4dTemplateID,
			Subject:    "Your Space setup is incomplete",
			BodyLines:  []string{"Hey,", "Your Ente Space setup is still incomplete.", "Finish your profile to start sharing everyday photos privately with friends and family.", "If anything feels unclear, reply here and we'll help!"},
			CTALabel:   "Finish setup",
			Candidates: func(ctx context.Context, now int64, limit int) ([]spacerepo.SpaceDripCandidate, error) {
				return c.DripsRepo.ListProfileMissingCandidates(ctx, now, now-4*day, []string{SpaceDripProfileMissing4dTemplateID}, limit)
			},
		},
		{
			TemplateID: SpaceDripProfileMissing24hTemplateID,
			Subject:    "Finish setting up Ente Space",
			BodyLines:  []string{"Hey,", "You're almost done setting up Ente Space.", "Finish your profile to start sharing everyday photos with friends and family."},
			CTALabel:   "Finish setup",
			Candidates: func(ctx context.Context, now int64, limit int) ([]spacerepo.SpaceDripCandidate, error) {
				return c.DripsRepo.ListProfileMissingCandidates(ctx, now, now-day, []string{SpaceDripProfileMissing24hTemplateID, SpaceDripProfileMissing4dTemplateID}, limit)
			},
		},
		{
			TemplateID: SpaceDripInvitePeople4dTemplateID,
			Subject:    "Add close friends and family",
			BodyLines:  []string{"Hey,", "You haven't invited anyone to your Space yet.", "Start with close friends or family you'd like to share everyday photos with. You can add more people later.", "If anything feels unclear, reply here and we'll help!"},
			CTALabel:   "Open Ente Space",
			Candidates: func(ctx context.Context, now int64, limit int) ([]spacerepo.SpaceDripCandidate, error) {
				return c.DripsRepo.ListInvitePeopleCandidates(ctx, now-4*day, []string{SpaceDripInvitePeople4dTemplateID}, limit)
			},
		},
		{
			TemplateID: SpaceDripInvitePeople24hTemplateID,
			Subject:    "Invite friends and family",
			BodyLines:  []string{"Hey,", "Your space is ready!", "Invite friends and family to share everyday photos privately."},
			CTALabel:   "Open Ente Space",
			Candidates: func(ctx context.Context, now int64, limit int) ([]spacerepo.SpaceDripCandidate, error) {
				return c.DripsRepo.ListInvitePeopleCandidates(ctx, now-day, []string{SpaceDripInvitePeople24hTemplateID, SpaceDripInvitePeople4dTemplateID}, limit)
			},
		},
		{
			TemplateID: SpaceDripFirstPost4dTemplateID,
			Subject:    "Share a recent photo",
			BodyLines:  []string{"Hey,", "You haven't posted to your Space yet.", "Pick something recent and share it. It doesn't need to be perfect!", "If anything feels unclear, reply here and we'll help!"},
			CTALabel:   "Open Ente Space",
			Candidates: func(ctx context.Context, now int64, limit int) ([]spacerepo.SpaceDripCandidate, error) {
				return c.DripsRepo.ListFirstPostCandidates(ctx, now-4*day, []string{SpaceDripFirstPost4dTemplateID}, limit)
			},
		},
		{
			TemplateID: SpaceDripFirstPost24hTemplateID,
			Subject:    "Share your first photo",
			BodyLines:  []string{"Hey,", "You've got people in your Space now!", "Share something recent with them."},
			CTALabel:   "Open Ente Space",
			Candidates: func(ctx context.Context, now int64, limit int) ([]spacerepo.SpaceDripCandidate, error) {
				return c.DripsRepo.ListFirstPostCandidates(ctx, now-day, []string{SpaceDripFirstPost24hTemplateID, SpaceDripFirstPost4dTemplateID}, limit)
			},
		},
		{
			TemplateID: SpaceDripFeedback7dTemplateID,
			Subject:    "Thoughts on Ente Space?",
			BodyLines:  []string{"Hey,", "You've been using Ente Space for a few days.", "What do you love about it? What should we improve?", "Reply to this email or drop a message on our Discord!"},
			Candidates: func(ctx context.Context, now int64, limit int) ([]spacerepo.SpaceDripCandidate, error) {
				return c.DripsRepo.ListFeedbackCandidates(ctx, now-7*day, []string{SpaceDripFeedback7dTemplateID}, limit)
			},
		},
	}
}

func (c *SpaceDripController) processSpaceDripStage(ctx context.Context, stage spaceDripStage, now int64, limit int, handledThisRun map[int64]struct{}) (int, error) {
	candidates, err := stage.Candidates(ctx, now, limit)
	if err != nil {
		return 0, err
	}
	if len(candidates) == limit {
		log.WithFields(log.Fields{
			"template_id": stage.TemplateID,
			"batch_size":  limit,
		}).Warn("Space drip candidate batch reached limit")
	}
	userIDs := make([]int64, 0, len(candidates))
	for _, candidate := range candidates {
		if _, handled := handledThisRun[candidate.UserID]; handled {
			continue
		}
		userIDs = append(userIDs, candidate.UserID)
	}
	if len(userIDs) == 0 {
		return 0, nil
	}
	users, err := c.UserRepo.GetActiveUsersForIds(userIDs)
	if err != nil {
		return 0, err
	}
	sent := 0
	for _, candidate := range candidates {
		if _, alreadyHandled := handledThisRun[candidate.UserID]; alreadyHandled {
			continue
		}
		handledThisRun[candidate.UserID] = struct{}{}
		user := users[candidate.UserID]
		if user == nil || strings.TrimSpace(user.Email) == "" {
			continue
		}
		if err := sendSpaceDripEmail(
			[]string{user.Email},
			"Ente Space",
			"space@ente.com",
			stage.Subject,
			spaceDripTemplate,
			map[string]interface{}{
				"BodyLines": stage.BodyLines,
				"CTAURL":    spaceAppURL(),
				"CTALabel":  stage.CTALabel,
			},
			nil,
		); err != nil {
			log.WithFields(log.Fields{
				"user_id":     candidate.UserID,
				"template_id": stage.TemplateID,
			}).WithError(err).Error("Error sending space drip email")
			continue
		}
		sent++
		if err := c.NotificationHistoryRepo.SetLastNotificationTimeToNow(candidate.UserID, stage.TemplateID); err != nil {
			return sent, fmt.Errorf("failed to record space drip history for user %d template %s: %w", candidate.UserID, stage.TemplateID, err)
		}
	}
	return sent, nil
}
