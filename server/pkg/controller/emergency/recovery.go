package emergency

import (
	"context"
	"fmt"
	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/repo/emergency"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	log "github.com/sirupsen/logrus"
	stime "time"
)

const (
	_recoveryReminderLock = "recoveryReminderLock"
)

func (c *Controller) GetRecoveryInfo(ctx *gin.Context,
	userID int64,
	sessionID uuid.UUID,
) (*string, *ente.KeyAttributes, error) {
	contact, err := c.checkRecoveryAndGetContact(ctx, userID, sessionID)
	if err != nil {
		return nil, nil, err
	}
	recoveryTarget, err := c.UserRepo.Get(contact.UserID)
	if err != nil {
		return nil, nil, err
	}
	keyAttr, err := c.UserRepo.GetKeyAttributes(recoveryTarget.ID)
	if err != nil {
		return nil, nil, err
	}
	return contact.EncryptedKey, &keyAttr, nil
}

func (c *Controller) InitChangePassword(ctx *gin.Context, userID int64, request ente.RecoverySrpSetupRequest) (*ente.SetupSRPResponse, error) {
	sessionID := request.RecoveryID
	contact, err := c.checkRecoveryAndGetContact(ctx, userID, sessionID)
	if err != nil {
		return nil, err
	}
	resp, err := c.UserCtrl.SetupSRP(ctx, contact.UserID, request.SetUpSRPReq)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return resp, nil
}

func (c *Controller) ChangePassword(ctx *gin.Context, userID int64, request ente.RecoveryUpdateSRPAndKeysRequest) (*ente.UpdateSRPSetupResponse, error) {
	sessionID := request.RecoveryID
	contact, err := c.checkRecoveryAndGetContact(ctx, userID, sessionID)
	if err != nil {
		return nil, err
	}
	// disable 2fa
	if disableErr := c.UserCtrl.DisableTwoFactor(contact.UserID); disableErr != nil {
		return nil, stacktrace.Propagate(disableErr, "failed to disable 2fa")
	}
	if disableErr := c.PasskeyController.RemovePasskey2FA(contact.UserID); disableErr != nil {
		return nil, stacktrace.Propagate(disableErr, "failed to disable passkey")
	}
	resp, err := c.UserCtrl.UpdateSrpAndKeyAttributes(ctx, contact.UserID, request.UpdateSrp, false)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}

	hasUpdate, err := c.Repo.UpdateRecoveryStatusForSession(ctx, sessionID, contact.UserID, contact.EmergencyContactID, ente.RecoveryStatusRecovered)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to update recovery status")
	}
	if !hasUpdate {
		log.WithField("userID", userID).WithField("req", request).
			Warn("no row updated while marking recovery complete")
	} else {
		go c.sendRecoveryNotification(ctx, contact.UserID, contact.EmergencyContactID, ente.RecoveryStatusRecovered, nil)
	}

	return resp, nil
}

func (c *Controller) checkRecoveryAndGetContact(ctx *gin.Context,
	userID int64,
	sessionID uuid.UUID) (*emergency.ContactRow, error) {
	recoverRow, err := c.Repo.GetRecoverRowByID(ctx, sessionID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if recoverRow.EmergencyContactID != userID {
		return nil, stacktrace.Propagate(ente.ErrPermissionDenied, "only the emergency contact can get recovery info")
	}
	if err = recoverRow.CanRecover(); err != nil {
		return nil, stacktrace.Propagate(ente.NewBadRequestWithMessage(err.Error()), "")
	}
	contact, err := c.Repo.GetActiveEmergencyContact(ctx, recoverRow.UserID, recoverRow.EmergencyContactID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if contact.EncryptedKey == nil {
		return nil, stacktrace.Propagate(ente.ErrNotFound, "no encrypted key found")
	}
	return contact, nil
}

func (c *Controller) SendRecoveryReminder() {
	if c.isReminderCronRunning {
		return
	}
	c.isReminderCronRunning = true
	defer func() {
		c.isReminderCronRunning = false
	}()
	lockStatus := c.LockCtrl.TryLock(_recoveryReminderLock, time.MicrosecondsAfterHours(1))
	if !lockStatus {
		log.Error("Could not acquire lock to send storage limit exceeded mails")
		return
	}
	defer c.LockCtrl.ReleaseLock(_recoveryReminderLock)

	rows, err := c.Repo.GetActiveRecoveryForNotification()
	if err != nil {
		log.WithError(err).Error("failed to get recovery rows")
		return
	}

	if len(*rows) == 0 {
		return
	}
	log.Info(fmt.Sprintf("Found %d recovery rows", len(*rows)))
	microsecondsInDay := (stime.Hour * 24).Microseconds()
	for _, row := range *rows {
		logger := log.WithFields(log.Fields{
			"userID":         row.UserID,
			"contactID":      row.EmergencyContactID,
			"status":         row.Status,
			"waitTill":       row.WaitTill,
			"nextReminderAt": row.NextReminderAt,
			"sessionID":      row.ID,
		})

		daysLeft := (row.WaitTill - row.NextReminderAt) / microsecondsInDay
		logger.Infof("Days left: %d", daysLeft)
		if row.WaitTill < time.Microseconds() && row.Status == ente.RecoveryStatusWaiting {
			_, updateErr := c.Repo.UpdateRecoveryStatusForID(context.Background(), row.ID, ente.RecoveryStatusReady)
			if updateErr != nil {
				logger.WithError(updateErr).Error("failed to update recovery status")
				continue
			}

			go c.sendRecoveryNotification(context.Background(), row.UserID, row.EmergencyContactID, ente.RecoveryStatusReady, nil)
		} else if daysLeft >= 2 && row.Status == ente.RecoveryStatusWaiting {
			var (
				nextReminder int64
				shouldUpdate bool
			)
			if daysLeft > 9 {
				// schedule another reminder after 7 days
				nextReminder = row.NextReminderAt + int64(microsecondsInDay*7)
				shouldUpdate = true
			} else if daysLeft > 2 {
				// schedule the final reminder two days before waitTill
				nextReminder = row.WaitTill - int64(microsecondsInDay*2)
				shouldUpdate = true
			} else {
				// final reminder already sent; wait until recovery becomes ready
				nextReminder = row.WaitTill
				shouldUpdate = true
			}

			if shouldUpdate {
				if err := c.Repo.UpdateNextReminder(context.Background(), row.ID, nextReminder); err != nil {
					logger.WithError(err).Error("failed to update next reminder")
					continue
				}
			}

			if row.Status == ente.RecoveryStatusWaiting {
				go c.sendRecoveryNotification(context.Background(), row.UserID, row.EmergencyContactID, ente.RecoveryStatusWaiting, &daysLeft)
			} else {
				logger.Warnf("No need to send email with status %v", row.Status)
			}
		}
	}
}
