package api

import (
	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller/emergency"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"net/http"
)

// EmergencyHandler contains handlers for managing emergency contacts
type EmergencyHandler struct {
	Controller *emergency.Controller
}

// AddContact adds a new emergency contact for current user
func (h *EmergencyHandler) AddContact(c *gin.Context) {
	var request ente.AddContact
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Could not bind request params"))
		return
	}
	err := h.Controller.AddContact(c, auth.GetUserID(c.Request.Header), request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

func (h *EmergencyHandler) GetInfo(c *gin.Context) {
	resp, err := h.Controller.GetInfo(c, auth.GetUserID(c.Request.Header))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *EmergencyHandler) UpdateContact(c *gin.Context) {
	var request ente.UpdateContact
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(ente.NewBadRequestWithMessage("failed to validate req param"), "%v", err))
		return
	}
	err := h.Controller.UpdateContact(c, auth.GetUserID(c.Request.Header), request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

func (h *EmergencyHandler) UpdateRecoveryNotice(c *gin.Context) {
	var request ente.UpdateRecoveryNotice
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(ente.NewBadRequestWithMessage("failed to validate req param"), "%v", err))
		return
	}
	err := h.Controller.UpdateRecoveryNotice(c, auth.GetUserID(c.Request.Header), request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

func (h *EmergencyHandler) StartRecovery(c *gin.Context) {
	var request ente.ContactIdentifier
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(ente.NewBadRequestWithMessage("failed to validate req param"), "%v", err))
		return
	}
	err := h.Controller.StartRecovery(c, auth.GetUserID(c.Request.Header), request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

func (h *EmergencyHandler) StopRecovery(c *gin.Context) {
	var request ente.RecoveryIdentifier
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(ente.NewBadRequestWithMessage("failed to validate req param"), "%v", err))
		return
	}
	err := h.Controller.StopRecovery(c, auth.GetUserID(c.Request.Header), request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

func (h *EmergencyHandler) RejectRecovery(c *gin.Context) {
	var request ente.RecoveryIdentifier
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(ente.NewBadRequestWithMessage("failed to validate req param"), "%v", err))
		return
	}
	err := h.Controller.RejectRecovery(c, auth.GetUserID(c.Request.Header), request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

func (h *EmergencyHandler) ApproveRecovery(c *gin.Context) {
	var request ente.RecoveryIdentifier
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(ente.NewBadRequestWithMessage("failed to validate req param"), "%v", err))
		return
	}
	err := h.Controller.ApproveRecovery(c, auth.GetUserID(c.Request.Header), request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

func (h *EmergencyHandler) GetRecoveryInfo(c *gin.Context) {
	sessionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(ente.NewBadRequestWithMessage("failed to validate req param"), "%v", err))
		return
	}
	encRecovery, keyAttr, err := h.Controller.GetRecoveryInfo(c, auth.GetUserID(c.Request.Header), sessionID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"encryptedKey": encRecovery,
		"userKeyAttr":  keyAttr,
	})
}

func (h *EmergencyHandler) InitChangePassword(c *gin.Context) {
	var request ente.RecoverySrpSetupRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(ente.NewBadRequestWithMessage("failed to validate req param"), "%v", err))
		return
	}
	resp, err := h.Controller.InitChangePassword(c, auth.GetUserID(c.Request.Header), request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *EmergencyHandler) ChangePassword(c *gin.Context) {
	var request ente.RecoveryUpdateSRPAndKeysRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(ente.NewBadRequestWithMessage("failed to validate req param"), "%v", err))
		return
	}
	resp, err := h.Controller.ChangePassword(c, auth.GetUserID(c.Request.Header), request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, resp)
}
