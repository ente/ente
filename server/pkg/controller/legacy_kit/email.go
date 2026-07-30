package legacy_kit

import (
	"context"
	"fmt"

	legacykitrepo "github.com/ente/museum/pkg/repo/legacy_kit"
	"github.com/ente/museum/pkg/utils/email"
	"github.com/ente/stacktrace"
	log "github.com/sirupsen/logrus"
)

const (
	legacyKitBaseTemplate              = "legacy/legacy_base.html"
	legacyKitRecoveryStartedTemplate   = "legacy/kit_recovery_started.html"
	legacyKitRecoveryCompletedTemplate = "legacy/kit_recovery_completed.html"
)

func (c *Controller) sendRecoveryStartedNotification(ctx context.Context, userID int64, session *legacykitrepo.RecoverySessionRow, beneficiaryEmail *string) error {
	user, err := c.UserRepo.Get(userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to load legacy kit owner")
	}
	templateData := map[string]interface{}{
		"AccountEmail":  user.Email,
		"RecoveryDelay": recoveryDelayLabel(session.EffectiveNoticePeriodHrs),
		"IsImmediate":   session.EffectiveNoticePeriodHrs == 0,
	}
	if beneficiaryEmail != nil && *beneficiaryEmail != "" {
		templateData["BeneficiaryEmail"] = *beneficiaryEmail
	}
	if err := email.SendTemplatedEmailV2(
		[]string{user.Email},
		"Ente",
		"team@ente.com",
		"Legacy Kit recovery initiated",
		legacyKitBaseTemplate,
		legacyKitRecoveryStartedTemplate,
		templateData,
		nil,
	); err != nil {
		log.WithError(err).WithField("user_id", userID).Error("failed to send legacy kit recovery started email")
		return stacktrace.Propagate(err, "failed to send legacy kit recovery started email")
	}
	return nil
}

func (c *Controller) sendRecoveryCompletedNotification(ctx context.Context, userID int64) error {
	user, err := c.UserRepo.Get(userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to load legacy kit owner")
	}
	if err := email.SendTemplatedEmailV2(
		[]string{user.Email},
		"Ente",
		"team@ente.com",
		"Legacy Kit recovery completed",
		legacyKitBaseTemplate,
		legacyKitRecoveryCompletedTemplate,
		map[string]interface{}{"AccountEmail": user.Email},
		nil,
	); err != nil {
		log.WithError(err).WithField("user_id", userID).Error("failed to send legacy kit recovery completed email")
		return stacktrace.Propagate(err, "failed to send legacy kit recovery completed email")
	}
	return nil
}

func recoveryDelayLabel(hours int32) string {
	switch hours {
	case 0:
		return "immediately"
	case 24:
		return "1 day"
	default:
		return fmt.Sprintf("%d days", hours/24)
	}
}
