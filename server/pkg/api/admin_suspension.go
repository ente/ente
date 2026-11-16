package api

import (
	"net/http"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/gin-gonic/gin"
)

func (h *AdminHandler) SuspendUser(c *gin.Context) {
	h.setUserSuspended(c, true)
}

func (h *AdminHandler) UnsuspendUser(c *gin.Context) {
	h.setUserSuspended(c, false)
}

func (h *AdminHandler) setUserSuspended(c *gin.Context, suspended bool) {
	if err := h.isFreshAdminToken(c); err != nil {
		handler.Error(c, err)
		return
	}
	var req struct {
		UserID int64 `json:"userID" binding:"required,gt=0"`
	}
	if err := handler.BindJSON(c, &req); err != nil {
		handler.Error(c, err)
		return
	}
	adminID := auth.GetUserID(c.Request.Header)
	if suspended && req.UserID == adminID {
		handler.Error(c, ente.NewBadRequestWithMessage("You cannot suspend your own account"))
		return
	}
	if err := h.UserController.SetSuspended(c, req.UserID, suspended); err != nil {
		handler.Error(c, err)
		return
	}
	action := "unsuspending"
	if suspended {
		action = "suspending"
	}
	h.notifyAdminAction(adminID, "%s account for %d", action, req.UserID)
	c.JSON(http.StatusOK, gin.H{})
}
