package api

import (
	"strings"

	"github.com/ente/museum/space/controller"
	"github.com/ente/museum/space/models"
	"github.com/gin-gonic/gin"
)

func (h *Handlers) GetWebPushVAPIDKey(c *gin.Context) {
	resp, err := h.Module.WebPush.VAPIDPublicKey()
	respondJSON(c, resp, err)
}

func (h *Handlers) UpsertWebPushSubscription(c *gin.Context) {
	var req models.SpaceWebPushSubscriptionRequest
	if !bindJSON(c, &req) {
		return
	}
	sessionToken := strings.TrimSpace(c.GetHeader(controller.SpaceBrowserSessionTokenHeader))
	resp, err := h.Module.WebPush.UpsertAccountSubscription(c, sessionToken, req)
	respondJSON(c, resp, err)
}

func (h *Handlers) DeleteWebPushSubscription(c *gin.Context) {
	var req models.SpaceWebPushUnsubscriptionRequest
	if !bindJSON(c, &req) {
		return
	}
	sessionToken := strings.TrimSpace(c.GetHeader(controller.SpaceBrowserSessionTokenHeader))
	err := h.Module.WebPush.DeleteAccountSubscription(c, sessionToken, req)
	respondStatus(c, err)
}

func (h *Handlers) UpsertSpaceLinkWebPushSubscription(c *gin.Context) {
	var req models.SpaceWebPushSubscriptionRequest
	if !bindJSON(c, &req) {
		return
	}
	resp, err := h.Module.WebPush.UpsertLinkSubscription(c, c.Param("spaceSlug"), req)
	respondJSON(c, resp, err)
}

func (h *Handlers) DeleteSpaceLinkWebPushSubscription(c *gin.Context) {
	var req models.SpaceWebPushUnsubscriptionRequest
	if !bindJSON(c, &req) {
		return
	}
	err := h.Module.WebPush.DeleteLinkSubscription(c, c.Param("spaceSlug"), req)
	respondStatus(c, err)
}
