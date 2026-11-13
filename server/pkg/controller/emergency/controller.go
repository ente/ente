package emergency

import (
	"fmt"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/controller/lock"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller/user"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/emergency"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
)

type Controller struct {
	Repo                  *emergency.Repository
	UserRepo              *repo.UserRepository
	UserLookup            controller.UserLookup
	UserCtrl              *user.UserController
	LockCtrl              *lock.LockController
	isReminderCronRunning bool
}

func (c *Controller) UpdateContact(ctx *gin.Context,
	userID int64,
	req ente.UpdateContact) error {
	if err := validateUpdateReq(userID, req); err != nil {
		return stacktrace.Propagate(err, "")
	}
	hasUpdate, cancelled, err := c.Repo.UpdateState(ctx, req.UserID, req.EmergencyContactID, req.State)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if !hasUpdate {
		log.WithField("userID", userID).WithField("req", req).
			Warn("No update applied for emergency contact")
	} else {
		status := ente.RecoveryStatusStopped
		if req.State == ente.UserRevokedContact {
			status = ente.RecoveryStatusRejected
		}
		for range cancelled {
			go c.sendRecoveryNotification(ctx, req.UserID, req.EmergencyContactID, status, nil)
		}
		go c.sendContactNotification(ctx, req.UserID, req.EmergencyContactID, req.State)
	}
	return nil
}

func (c *Controller) HandleAccountDeletion(ctx *gin.Context, userID int64, logger *log.Entry) error {
	logger.Info("Clean up emergency contacts on account deletion")
	contacts, err := c.Repo.GetActiveContactForUser(ctx, userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if len(contacts) == 0 {
		return nil
	}
	for _, contact := range contacts {
		if contact.UserID == userID {
			logger.Info("Removing emergency contact from user side")
			removeErr := c.UpdateContact(ctx, userID, ente.UpdateContact{
				UserID:             userID,
				EmergencyContactID: contact.EmergencyContactID,
				State:              ente.UserRevokedContact,
			})
			if removeErr != nil {
				return stacktrace.Propagate(removeErr, "")
			}
		} else {
			logger.Info("Removing user from emergency contact side")
			leaveErr := c.UpdateContact(ctx, userID, ente.UpdateContact{
				UserID:             contact.UserID,
				EmergencyContactID: userID,
				State:              ente.ContactLeft,
			})
			if leaveErr != nil {
				return stacktrace.Propagate(leaveErr, "")
			}
		}
	}
	return nil
}

func validateUpdateReq(userID int64, req ente.UpdateContact) error {
	if req.EmergencyContactID == req.UserID {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("contact and user can not be same"), "")
	}
	if req.EmergencyContactID != userID && req.UserID != userID {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "user can only update his own state")
	}

	isActorContact := userID == req.EmergencyContactID
	if isActorContact {
		if req.State == ente.ContactAccepted ||
			req.State == ente.ContactLeft ||
			req.State == ente.ContactDenied {
			return nil
		}
		return stacktrace.Propagate(ente.NewBadRequestWithMessage(fmt.Sprintf("Can not update state to %s", req.State)), "")
	} else {
		if req.State == ente.UserInvitedContact ||
			req.State == ente.UserRevokedContact {
			return nil
		}
		return stacktrace.Propagate(ente.NewBadRequestWithMessage(fmt.Sprintf("Can not update state to %s", req.State)), "")
	}
}
