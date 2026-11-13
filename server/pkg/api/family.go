package api

import (
	"net/http"

	"github.com/ente/museum/pkg/controller/family"
	"github.com/ente/stacktrace"
	"github.com/google/uuid"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/gin-gonic/gin"
)

type FamilyHandler struct {
	Controller *family.Controller
}

func (h *FamilyHandler) CreateFamily(c *gin.Context) {
	err := h.Controller.CreateFamily(c, auth.GetUserID(c.Request.Header))

	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

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

func (h *FamilyHandler) FetchMembers(c *gin.Context) {
	members, err := h.Controller.FetchMembers(c, auth.GetUserID(c.Request.Header))

	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, members)
}

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

func (h *FamilyHandler) Leave(c *gin.Context) {
	err := h.Controller.LeaveFamily(c, auth.GetUserID(c.Request.Header))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

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

func (h *FamilyHandler) GetInviteInfo(c *gin.Context) {
	inviteToken := c.Param("token")
	response, err := h.Controller.InviteInfo(c, inviteToken)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, response)
}
