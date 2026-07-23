package api

import (
	"net/http"

	"github.com/ente/museum/ente"
	entity "github.com/ente/museum/ente/storagebonus"
	"github.com/ente/museum/pkg/controller/storagebonus"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

type StorageBonusHandler struct {
	Controller *storagebonus.Controller
}

func (h StorageBonusHandler) GetReferralView(context *gin.Context) {
	response, err := h.Controller.GetUserReferralView(context)
	if err != nil {
		handler.Error(context, stacktrace.Propagate(err, ""))
		return
	}
	context.JSON(http.StatusOK, response)
}

func (h StorageBonusHandler) UpdateReferralCode(context *gin.Context) {
	var request entity.UpdateReferralCodeRequest
	if err := handler.BindJSON(context, &request); err != nil {
		handler.Error(context, stacktrace.Propagate(ente.NewBadRequestWithMessage(err.Error()), ""))
		return
	}
	userID := auth.GetUserID(context.Request.Header)
	err := h.Controller.UpdateReferralCode(context, userID, request.Code, false)
	if err != nil {
		handler.Error(context, stacktrace.Propagate(err, ""))
		return
	}
	context.JSON(http.StatusOK, gin.H{})
}

func (h StorageBonusHandler) GetStorageBonusDetails(context *gin.Context) {
	response, err := h.Controller.GetStorageBonusDetailResponse(context, auth.GetUserID(context.Request.Header))
	if err != nil {
		handler.Error(context, stacktrace.Propagate(err, ""))
		return
	}
	context.JSON(http.StatusOK, response)
}

func (h StorageBonusHandler) ClaimReferral(c *gin.Context) {
	code := c.Query("code")
	if code == "" {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "referral code is required"))
		return
	}
	err := h.Controller.ApplyReferralCode(c, code)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)

}
