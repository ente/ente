package api

import (
	"net/http"

	"github.com/ente/museum/ente"
	legacykit "github.com/ente/museum/pkg/controller/legacy_kit"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type LegacyKitHandler struct {
	Controller *legacykit.Controller
}

func (h *LegacyKitHandler) Create(c *gin.Context) {
	var request ente.CreateLegacyKitRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "could not bind request params"))
		return
	}
	resp, err := h.Controller.CreateKit(c, auth.GetUserID(c.Request.Header), request)
	if err != nil {
		handler.Error(c, err)
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *LegacyKitHandler) List(c *gin.Context) {
	resp, err := h.Controller.ListKits(c, auth.GetUserID(c.Request.Header))
	if err != nil {
		handler.Error(c, err)
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *LegacyKitHandler) DownloadContent(c *gin.Context) {
	kitID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(ente.NewBadRequestWithMessage("invalid legacy kit id"), "%v", err))
		return
	}
	resp, err := h.Controller.DownloadKitContent(c, auth.GetUserID(c.Request.Header), kitID)
	if err != nil {
		handler.Error(c, err)
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *LegacyKitHandler) OwnerRecoverySession(c *gin.Context) {
	kitID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(ente.NewBadRequestWithMessage("invalid legacy kit id"), "%v", err))
		return
	}
	resp, err := h.Controller.GetOwnerRecoverySession(c, auth.GetUserID(c.Request.Header), kitID)
	if err != nil {
		handler.Error(c, err)
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *LegacyKitHandler) UpdateRecoveryNotice(c *gin.Context) {
	var request ente.UpdateLegacyKitRecoveryNoticeRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "could not bind request params"))
		return
	}
	if err := h.Controller.UpdateRecoveryNotice(c, auth.GetUserID(c.Request.Header), request); err != nil {
		handler.Error(c, err)
		return
	}
	c.Status(http.StatusOK)
}

func (h *LegacyKitHandler) Delete(c *gin.Context) {
	kitID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(ente.NewBadRequestWithMessage("invalid legacy kit id"), "%v", err))
		return
	}
	if err := h.Controller.DeleteKit(c, auth.GetUserID(c.Request.Header), kitID); err != nil {
		handler.Error(c, err)
		return
	}
	c.Status(http.StatusOK)
}

func (h *LegacyKitHandler) BlockRecovery(c *gin.Context) {
	var request ente.LegacyKitOwnerActionRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "could not bind request params"))
		return
	}
	if err := h.Controller.BlockRecovery(c, auth.GetUserID(c.Request.Header), request.KitID); err != nil {
		handler.Error(c, err)
		return
	}
	c.Status(http.StatusOK)
}

func (h *LegacyKitHandler) CreateChallenge(c *gin.Context) {
	var request ente.LegacyKitChallengeRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "could not bind request params"))
		return
	}
	resp, err := h.Controller.CreateChallenge(c, request)
	if err != nil {
		handler.Error(c, err)
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *LegacyKitHandler) OpenRecovery(c *gin.Context) {
	var request ente.LegacyKitOpenRecoveryRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "could not bind request params"))
		return
	}
	resp, err := h.Controller.OpenRecovery(c, request)
	if err != nil {
		handler.Error(c, err)
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *LegacyKitHandler) Session(c *gin.Context) {
	var request ente.LegacyKitSessionRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "could not bind request params"))
		return
	}
	resp, err := h.Controller.GetSession(c, request)
	if err != nil {
		handler.Error(c, err)
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *LegacyKitHandler) RecoveryInfo(c *gin.Context) {
	var request ente.LegacyKitSessionRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "could not bind request params"))
		return
	}
	resp, err := h.Controller.GetRecoveryInfo(c, request)
	if err != nil {
		handler.Error(c, err)
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *LegacyKitHandler) InitChangePassword(c *gin.Context) {
	var request ente.LegacyKitRecoverySrpSetupRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "could not bind request params"))
		return
	}
	resp, err := h.Controller.InitChangePassword(c, request)
	if err != nil {
		handler.Error(c, err)
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *LegacyKitHandler) ChangePassword(c *gin.Context) {
	var request ente.LegacyKitRecoveryUpdateSRPRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "could not bind request params"))
		return
	}
	resp, err := h.Controller.ChangePassword(c, request)
	if err != nil {
		handler.Error(c, err)
		return
	}
	c.JSON(http.StatusOK, resp)
}
