package api

import (
	"github.com/ente/museum/space/models"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/gin-gonic/gin"
)

func (h *Handlers) CreateMessage(c *gin.Context, space *spacerepo.SpaceRecord) {
	var req models.CreateMessageRequest
	if !bindJSON(c, &req) {
		return
	}
	friendSpaceID, ok := stringParam(c, "friendSpaceID")
	if !ok {
		return
	}
	resp, err := h.Module.Messages.Create(c, space, friendSpaceID, req)
	respondJSON(c, resp, err)
}

func (h *Handlers) LikeMessage(c *gin.Context, space *spacerepo.SpaceRecord) {
	h.setMessageLike(c, space, true)
}

func (h *Handlers) UnlikeMessage(c *gin.Context, space *spacerepo.SpaceRecord) {
	h.setMessageLike(c, space, false)
}

func (h *Handlers) setMessageLike(c *gin.Context, space *spacerepo.SpaceRecord, like bool) {
	messageID, ok := stringParam(c, "messageID")
	if !ok {
		return
	}
	resp, err := h.Module.Messages.SetLike(c, space, messageID, like)
	respondJSON(c, resp, err)
}

func (h *Handlers) DeleteMessage(c *gin.Context, space *spacerepo.SpaceRecord) {
	messageID, ok := stringParam(c, "messageID")
	if !ok {
		return
	}
	err := h.Module.Messages.Delete(c, space, messageID)
	respondJSON(c, nil, err)
}

func (h *Handlers) ReplyToPost(c *gin.Context, space *spacerepo.SpaceRecord) {
	var req models.CreateMessageRequest
	if !bindJSON(c, &req) {
		return
	}
	postID, ok := positiveInt64Param(c, "postID")
	if !ok {
		return
	}
	resp, err := h.Module.Messages.ReplyToPost(c, space, postID, req)
	respondJSON(c, resp, err)
}

func (h *Handlers) ListConversations(c *gin.Context, space *spacerepo.SpaceRecord) {
	resp, err := h.Module.Messages.ListConversations(c, space)
	respondJSON(c, resp, err)
}

func (h *Handlers) ListMessageThread(c *gin.Context, space *spacerepo.SpaceRecord) {
	var req models.ListMessageThreadRequest
	if !bindQuery(c, &req) {
		return
	}
	friendSpaceID, ok := stringParam(c, "friendSpaceID")
	if !ok {
		return
	}
	resp, err := h.Module.Messages.ListThread(c, space, friendSpaceID, req)
	respondJSON(c, resp, err)
}
