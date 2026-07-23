package api

import (
	"net/http"

	"github.com/ente/museum/pkg/controller/family"
	"github.com/ente/stacktrace"
	"github.com/google/uuid"

	// "github.com/gin-contrib/requestid"
	// log "github.com/sirupsen/logrus"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/handler"

	// "github.com/ente/museum/pkg/utils/time"
	"github.com/gin-gonic/gin"
)

// FamilyHandler contains handlers for managing family plans
type FamilyHandler struct {
	Controller *family.Controller
}

// CreateFamily creates a family with current user as admin member
func (h *FamilyHandler) CreateFamily(c *gin.Context) {
	err := h.Controller.CreateFamily(c, auth.GetUserID(c.Request.Header))

	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

// InviteMember sends out invitation to a user for joining acting user's family plan
func (h *FamilyHandler) InviteMember(c *gin.Context) {
	var request ente.InviteMemberRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Could not bind request params"))
		return
	}

	err := h.Controller.InviteMember(c, auth.GetUserID(c.Request.Header), request.Email, request.StorageLimit)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

// FetchMembers returns information about members who have been invited (only for admin) or are part of family plan
func (h *FamilyHandler) FetchMembers(c *gin.Context) {
	members, err := h.Controller.FetchMembers(c, auth.GetUserID(c.Request.Header))

	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, members)
}

// RemoveMember removes the member from the family group
func (h *FamilyHandler) RemoveMember(c *gin.Context) {
	familyMembershipID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "failed to find valid uuid"))
		return
	}
	err = h.Controller.RemoveMember(c, auth.GetUserID(c.Request.Header), familyMembershipID)

	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

// Leave family
func (h *FamilyHandler) Leave(c *gin.Context) {
	err := h.Controller.LeaveFamily(c, auth.GetUserID(c.Request.Header))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

// RevokeInvite removes the invite for given user as long it's still in invite state
func (h *FamilyHandler) RevokeInvite(c *gin.Context) {
	familyMembershipID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "failed to find valid uuid"))
		return
	}

	err = h.Controller.RevokeInvite(c, auth.GetUserID(c.Request.Header), familyMembershipID)

	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

// AcceptInvite allows user to join the family based on the token
func (h *FamilyHandler) AcceptInvite(c *gin.Context) {
	var request ente.AcceptInviteRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Could not bind request params"))
		return
	}

	response, err := h.Controller.AcceptInvite(c, request.Token)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, response)
}

// ModifyStorageLimit allows adminUser to Modify the storage for a member in the Family.
func (h *FamilyHandler) ModifyStorageLimit(c *gin.Context) {
	var request ente.ModifyMemberStorage
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Could not bind request params"))
		return
	}

	err := h.Controller.ModifyMemberStorage(c, auth.GetUserID(c.Request.Header), request.ID, request.StorageLimit)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

// GetInviteInfo returns basic information about invitor/admin as long as the invite is valid
func (h *FamilyHandler) GetInviteInfo(c *gin.Context) {
	inviteToken := c.Param("token")
	response, err := h.Controller.InviteInfo(c, inviteToken)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, response)
}
