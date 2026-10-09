package api

import (
	"github.com/ente/museum/space/models"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/gin-gonic/gin"
)

func (h *Handlers) ListUnreadActivities(c *gin.Context, space *spacerepo.SpaceRecord) {
	var req models.ListUnreadActivitiesRequest
	if !bindQuery(c, &req) {
		return
	}
	resp, err := h.Module.Read.ListUnreadActivities(c, space, req)
	respondJSON(c, resp, err)
}

func (h *Handlers) GetUnreadStatus(c *gin.Context, space *spacerepo.SpaceRecord) {
	resp, err := h.Module.Read.GetUnreadStatus(c, space)
	respondJSON(c, resp, err)
}

func (h *Handlers) MarkNotificationsRead(c *gin.Context, space *spacerepo.SpaceRecord) {
	friendSpaceID, ok := stringParam(c, "friendSpaceID")
	if !ok {
		return
	}
	resp, err := h.Module.Read.MarkNotificationsRead(c, space, friendSpaceID)
	respondJSON(c, resp, err)
}
