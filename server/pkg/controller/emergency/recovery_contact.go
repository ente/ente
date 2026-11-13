package emergency

import (
	"github.com/ente/museum/ente"
	emergencyRepo "github.com/ente/museum/pkg/repo/emergency"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
)

func (c *Controller) StartRecovery(ctx *gin.Context,
	actorUserID int64,
	req ente.ContactIdentifier) error {
	if req.EmergencyContactID == req.UserID {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("contact and user can not be same"), "")
	}
	if req.EmergencyContactID != actorUserID {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "only the emergency contact can start recovery")
	}

	hasUpdate, contact, err := c.Repo.InsertIntoRecovery(ctx, req)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if !hasUpdate {
		log.WithField("userID", actorUserID).WithField("req", req).
			Warn("No need to send email")
	} else {
		recoveryNoticeInDays := int64(contact.NoticePeriodInHrs / 24)
		go c.sendRecoveryNotification(ctx, req.UserID, req.EmergencyContactID, ente.RecoveryStatusInitiated, &recoveryNoticeInDays)
	}
	return nil
}

func (c *Controller) RejectRecovery(ctx *gin.Context,
	userID int64,
	req ente.RecoveryIdentifier) error {
	if req.EmergencyContactID == req.UserID {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("contact and user can not be same"), "")
	}
	if req.UserID != userID {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "only account owner can reject recovery")
	}
	session, err := c.getRecoverySessionMatchingRequest(ctx, req)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if session.UserID != userID {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "only account owner can reject recovery")
	}
	hasUpdate, err := c.Repo.UpdateRecoveryStatusForSession(ctx, session.ID, session.UserID, session.EmergencyContactID, ente.RecoveryStatusRejected)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if !hasUpdate {
		return stacktrace.Propagate(ente.NewConflictError("recovery session is no longer active"), "")
	}
	go c.sendRecoveryNotification(ctx, session.UserID, session.EmergencyContactID, ente.RecoveryStatusRejected, nil)
	return nil
}

func (c *Controller) ApproveRecovery(ctx *gin.Context,
	userID int64,
	req ente.RecoveryIdentifier) error {
	if req.EmergencyContactID == req.UserID {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("contact and user can not be same"), "")
	}
	session, err := c.getRecoverySessionMatchingRequest(ctx, req)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if session.UserID != userID {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "only account owner can approve recovery")
	}
	hasUpdate, err := c.Repo.UpdateRecoveryStatusForSession(ctx, session.ID, session.UserID, session.EmergencyContactID, ente.RecoveryStatusReady)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if !hasUpdate {
		log.WithField("userID", userID).WithField("req", req).
			Warn("no row updated while approving recovery")
	} else {
		go c.sendRecoveryNotification(ctx, session.UserID, session.EmergencyContactID, ente.RecoveryStatusReady, nil)
	}
	return nil
}

func (c *Controller) StopRecovery(ctx *gin.Context,
	userID int64,
	req ente.RecoveryIdentifier) error {
	if req.EmergencyContactID == req.UserID {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("contact and user can not be same"), "")
	}
	if req.EmergencyContactID != userID {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "only the emergency contact can stop recovery")
	}
	session, err := c.getRecoverySessionMatchingRequest(ctx, req)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if session.EmergencyContactID != userID {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "only the emergency contact can stop recovery")
	}
	hasUpdate, err := c.Repo.UpdateRecoveryStatusForSession(ctx, session.ID, session.UserID, session.EmergencyContactID, ente.RecoveryStatusStopped)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if !hasUpdate {
		return stacktrace.Propagate(ente.NewConflictError("recovery session is no longer active"), "")
	}
	go c.sendRecoveryNotification(ctx, session.UserID, session.EmergencyContactID, ente.RecoveryStatusStopped, nil)
	return nil
}

func (c *Controller) getRecoverySessionMatchingRequest(ctx *gin.Context, req ente.RecoveryIdentifier) (*emergencyRepo.RecoverRow, error) {
	session, err := c.Repo.GetRecoverRowByID(ctx, req.ID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if session.UserID != req.UserID || session.EmergencyContactID != req.EmergencyContactID {
		return nil, stacktrace.Propagate(ente.ErrPermissionDenied, "recovery session does not match request")
	}
	return session, nil
}
