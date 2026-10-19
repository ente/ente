package api

import (
	"github.com/ente/museum/space/models"
	"github.com/ente/museum/space/repo"
	"github.com/gin-gonic/gin"
)

func (h *Handlers) ListNotifications(c *gin.Context, space *repo.SpaceRecord) {
	var req models.ListNotificationsRequest
	if !bindQuery(c, &req) {
		return
	}
	resp, err := h.Module.Notifications.List(c, space, req)
	respondJSON(c, resp, err)
}

func (h *Handlers) GetNotificationUnread(c *gin.Context, space *repo.SpaceRecord) {
	resp, err := h.Module.Notifications.Unread(c, space)
	respondJSON(c, resp, err)
}

func (h *Handlers) ReadNotifications(c *gin.Context, space *repo.SpaceRecord) {
	var req models.ReadNotificationsRequest
	if !bindJSON(c, &req) {
		return
	}
	respondStatus(c, h.Module.Notifications.MarkRead(c, space, req))
}
