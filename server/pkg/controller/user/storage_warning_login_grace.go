package user

import (
	stdtime "time"

	"github.com/ente/museum/pkg/repo"
	emailUtil "github.com/ente/museum/pkg/utils/email"
	"github.com/sirupsen/logrus"
)

const (
	storageWarningLoginGraceBaseTemplate = "ente_base.html"
	storageWarningLoginGraceTemplate     = "storage-warning/storage_warning_login_grace.html"
	storageWarningLoginGraceSubject      = "Temporary access restored to your Ente account"
	storageWarningLoginGraceFromName     = "Ente"
	storageWarningLoginGraceFromEmail    = "support@ente.com"
)

var sendStorageWarningLoginGraceEmail = emailUtil.SendTemplatedEmailV2

// UnblockStorageWarningDeletionLogin grants a temporary login grace. It clears
// the terminal login-block rows, but it does not reverse every side effect of
// the original access reset such as sharing or family membership changes.
func (c *UserController) UnblockStorageWarningDeletionLogin(userID int64, logger *logrus.Entry) error {
	if c.NotificationHistoryRepo == nil {
		return nil
	}

	graceUntil, granted, err := c.NotificationHistoryRepo.GrantStorageWarningLoginGrace(userID)
	if err != nil {
		return err
	}
	if !granted {
		if logger != nil {
			logger.Info("Skipping storage warning login grace: no terminal login block found")
		}
		return nil
	}

	c.sendStorageWarningLoginGraceEmail(userID, graceUntil, logger)
	return nil
}

func (c *UserController) sendStorageWarningLoginGraceEmail(userID int64, graceUntil int64, logger *logrus.Entry) {
	if c.UserRepo == nil {
		if logger != nil {
			logger.Warn("Skipping storage warning login grace email: user repo is not configured")
		}
		return
	}

	user, err := c.UserRepo.GetUserByIDInternal(userID)
	if err != nil {
		if logger != nil {
			logger.WithError(err).Warn("Failed to fetch user for storage warning login grace email")
		}
		return
	}

	templateData := map[string]interface{}{
		"AccountEmail": user.Email,
		"GraceUntil":   formatStorageWarningLoginGraceUntil(graceUntil),
		"GraceDays":    repo.StorageWarningLoginGraceDays,
	}
	err = sendStorageWarningLoginGraceEmail(
		[]string{user.Email},
		storageWarningLoginGraceFromName,
		storageWarningLoginGraceFromEmail,
		storageWarningLoginGraceSubject,
		storageWarningLoginGraceBaseTemplate,
		storageWarningLoginGraceTemplate,
		templateData,
		nil,
	)
	if err != nil && logger != nil {
		logger.WithError(err).Warn("Failed to send storage warning login grace email")
	}
}

func formatStorageWarningLoginGraceUntil(microseconds int64) string {
	if microseconds <= 0 {
		return ""
	}
	return stdtime.UnixMicro(microseconds).UTC().Format("January 2, 2006 at 15:04 UTC")
}
