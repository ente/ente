package emergency

import (
	"context"
	"fmt"

	"github.com/ente/museum/ente"
	emailUtil "github.com/ente/museum/pkg/utils/email"
	"github.com/ente/stacktrace"
	log "github.com/sirupsen/logrus"
)

const (
	BaseTemplate           string = "legacy/legacy_base.html"
	InviteTemplate         string = "legacy/legacy_invite.html"
	AcceptedTemplate       string = "legacy/legacy_invite_accepted.html"
	RejectedInviteTemplate string = "legacy/legacy_invite_rejected.html"
	InviteSentTemplate     string = "legacy/legacy_invite_sent.html"
	LeftTemplate           string = "legacy/legacy_left.html"
	RemovedTemplate        string = "legacy/legacy_removed.html"

	RecoveryCancelledTemplate        string = "legacy/recovery_cancelled.html"
	RecoveryCompletedTrustedTemplate string = "legacy/recovery_completed_trusted.html"
	RecoveryCompletedLegacyTemplate  string = "legacy/recovery_completed_legacy.html"

	RecoveryReadyLegacyTemplate  string = "legacy/recovery_ready_legacy.html"
	RecoveryReadyTrustedTemplate string = "legacy/recovery_ready_trusted.html"

	RecoveryRejectedTemplate string = "legacy/recovery_rejected.html"
	RecoveryReminderTemplate string = "legacy/recovery_reminder.html"
	RecoveryStartedTemplate  string = "legacy/recovery_started.html"
)

type emailData struct {
	title        string
	templateName string
	emailTo      string
	templateData map[string]interface{}
	inlineImages []map[string]interface{}
}

func (c *Controller) createEmailData(legacyUser, trustedUser ente.User, newStatus ente.ContactState) ([]emailData, error) {
	templateData := map[string]interface{}{
		"LegacyContact":  legacyUser.Email,
		"TrustedContact": trustedUser.Email,
	}

	var emailContent []emailData
	switch newStatus {
	case ente.UserInvitedContact:
		emailContent = append(emailContent, emailData{
			title:        "You have been added as a trusted contact",
			templateName: InviteTemplate,
			emailTo:      trustedUser.Email,
			templateData: templateData,
			inlineImages: []map[string]interface{}{},
		})
		emailContent = append(emailContent, emailData{
			title:        "Trusted contact invited",
			templateName: InviteSentTemplate,
			emailTo:      legacyUser.Email,
			templateData: templateData,
			inlineImages: []map[string]interface{}{},
		})
	case ente.UserRevokedContact:
		emailContent = append(emailContent, emailData{
			title:        "Legacy account access removed",
			templateName: RemovedTemplate,
			emailTo:      trustedUser.Email,
			templateData: templateData,
			inlineImages: []map[string]interface{}{},
		})
	case ente.ContactLeft:
		emailContent = append(emailContent, emailData{
			title:        "Trusted contact removed",
			templateName: LeftTemplate,
			emailTo:      legacyUser.Email,
			templateData: templateData,
			inlineImages: []map[string]interface{}{},
		})
	case ente.ContactDenied:
		emailContent = append(emailContent, emailData{
			title:        "Legacy invite rejected",
			templateName: RejectedInviteTemplate,
			emailTo:      legacyUser.Email,
			templateData: templateData,
			inlineImages: []map[string]interface{}{},
		})
	case ente.ContactAccepted:
		emailContent = append(emailContent, emailData{
			title:        "Trusted contact added",
			templateName: AcceptedTemplate,
			emailTo:      legacyUser.Email,
			templateData: templateData,
			inlineImages: []map[string]interface{}{},
		})
	default:
		return nil, fmt.Errorf("unsupported status %s", newStatus)
	}
	return emailContent, nil
}

func (c *Controller) sendContactNotification(ctx context.Context, legacyUserID int64, trustedUserID int64, newStatus ente.ContactState) error {
	legacyUser, err := c.UserRepo.Get(legacyUserID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	trustedUser, err := c.UserRepo.Get(trustedUserID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	emailDatas, err := c.createEmailData(legacyUser, trustedUser, newStatus)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	for _, data := range emailDatas {
		content := data
		err = emailUtil.SendTemplatedEmailV2([]string{content.emailTo}, "Ente", "team@ente.com",
			content.title, BaseTemplate, content.templateName, content.templateData, content.inlineImages)
		if err != nil {
			log.WithError(err).WithFields(log.Fields{
				"state":    newStatus,
				"to":       content.emailTo,
				"template": content.templateName,
			}).Error("failed to send email")
			return stacktrace.Propagate(err, "")
		}
	}

	return nil
}

func (c *Controller) createRecoveryEmailData(legacyUser, trustedUser ente.User, newStatus ente.RecoveryStatus, daysLeft *int64) ([]emailData, error) {
	templateData := map[string]interface{}{
		"LegacyContact":  legacyUser.Email,
		"TrustedContact": trustedUser.Email,
	}
	if daysLeft != nil {
		templateData["DaysLeft"] = *daysLeft
	}

	var emailDatas []emailData

	switch newStatus {
	case ente.RecoveryStatusInitiated:
		if _, ok := templateData["DaysLeft"]; !ok {
			templateData["DaysLeft"] = int64(30)
		}
		emailDatas = append(emailDatas, emailData{
			title:        "Ente account recovery initiated",
			templateName: RecoveryStartedTemplate,
			emailTo:      legacyUser.Email,
			templateData: templateData,
			inlineImages: []map[string]interface{}{},
		})
	case ente.RecoveryStatusRecovered:
		emailDatas = append(emailDatas, emailData{
			title:        "Ente account password reset",
			templateName: RecoveryCompletedLegacyTemplate,
			emailTo:      legacyUser.Email,
			templateData: templateData,
			inlineImages: []map[string]interface{}{},
		})
		emailDatas = append(emailDatas, emailData{
			title:        "Ente account recovery successful",
			templateName: RecoveryCompletedTrustedTemplate,
			emailTo:      trustedUser.Email,
			templateData: templateData,
			inlineImages: []map[string]interface{}{},
		})

	case ente.RecoveryStatusStopped:
		emailDatas = append(emailDatas, emailData{
			title:        "Ente account recovery cancelled",
			templateName: RecoveryCancelledTemplate,
			emailTo:      legacyUser.Email,
			templateData: templateData,
			inlineImages: []map[string]interface{}{},
		})
	case ente.RecoveryStatusRejected:
		emailDatas = append(emailDatas, emailData{
			title:        "Ente account recovery blocked",
			templateName: RecoveryRejectedTemplate,
			emailTo:      trustedUser.Email,
			templateData: templateData,
			inlineImages: []map[string]interface{}{},
		})
	case ente.RecoveryStatusWaiting:
		emailDatas = append(emailDatas, emailData{
			title:        "Ente account recovery due",
			templateName: RecoveryReminderTemplate,
			emailTo:      legacyUser.Email,
			templateData: templateData,
			inlineImages: []map[string]interface{}{},
		})
	case ente.RecoveryStatusReady:
		emailDatas = append(emailDatas, emailData{
			title:        "Ente account recoverable",
			templateName: RecoveryReadyTrustedTemplate,
			emailTo:      trustedUser.Email,
			templateData: templateData,
			inlineImages: []map[string]interface{}{},
		})
		emailDatas = append(emailDatas, emailData{
			title:        "Ente account recoverable",
			templateName: RecoveryReadyLegacyTemplate,
			emailTo:      legacyUser.Email,
			templateData: templateData,
			inlineImages: []map[string]interface{}{},
		})
	default:
		return nil, fmt.Errorf("unsupported status %s", newStatus)
	}

	return emailDatas, nil
}

func (c *Controller) sendRecoveryNotification(ctx context.Context, legacyUserID int64, trustedUserID int64, newStatus ente.RecoveryStatus, daysLeft *int64) error {
	legacyUser, err := c.UserRepo.Get(legacyUserID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	trustedUser, err := c.UserRepo.Get(trustedUserID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	emailDatas, err := c.createRecoveryEmailData(legacyUser, trustedUser, newStatus, daysLeft)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	for _, data := range emailDatas {
		content := data
		err = emailUtil.SendTemplatedEmailV2([]string{content.emailTo}, "Ente", "team@ente.com",
			content.title, BaseTemplate, content.templateName, content.templateData, content.inlineImages)
		if err != nil {
			log.WithError(err).WithFields(log.Fields{
				"state":    newStatus,
				"to":       content.emailTo,
				"template": content.templateName,
			}).Error("failed to send email")
			return stacktrace.Propagate(err, "")
		}
	}

	return nil
}
