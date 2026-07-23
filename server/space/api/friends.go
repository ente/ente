package api

import (
	"github.com/ente/museum/space/models"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/gin-gonic/gin"
)

func (h *Handlers) AddFriend(c *gin.Context, space *spacerepo.SpaceRecord) {
	var req models.AddFriendPayload
	if !bindJSON(c, &req) {
		return
	}
	resp, err := h.Module.Friends.Add(c, space, req)
	respondJSON(c, resp, err)
}

func (h *Handlers) Unfriend(c *gin.Context, space *spacerepo.SpaceRecord) {
	var req models.FriendTargetPayload
	if !bindJSON(c, &req) {
		return
	}
	respondStatus(c, h.Module.Friends.Unfriend(c, space, req))
}

func (h *Handlers) ListFriendRequests(c *gin.Context, space *spacerepo.SpaceRecord) {
	resp, err := h.Module.Friends.ListRequests(c, space)
	respondJSON(c, resp, err)
}

func (h *Handlers) ConfirmFriendRequest(c *gin.Context, space *spacerepo.SpaceRecord) {
	var req models.ConfirmFriendRequestPayload
	if !bindJSON(c, &req) {
		return
	}
	requestID, ok := positiveInt64Param(c, "requestID")
	if !ok {
		return
	}
	resp, err := h.Module.Friends.ConfirmRequest(c, space, requestID, req)
	respondJSON(c, resp, err)
}

func (h *Handlers) DeleteFriendRequest(c *gin.Context, space *spacerepo.SpaceRecord) {
	requestID, ok := positiveInt64Param(c, "requestID")
	if !ok {
		return
	}
	respondStatus(c, h.Module.Friends.DeleteRequest(c, space, requestID))
}

func (h *Handlers) ListSpaceFriends(c *gin.Context, space *spacerepo.SpaceRecord) {
	resp, err := h.Module.Friends.ListFriends(c, space)
	respondJSON(c, resp, err)
}

func (h *Handlers) FriendRelationship(c *gin.Context, space *spacerepo.SpaceRecord) {
	var req models.FriendRelationshipRequest
	if !bindQuery(c, &req) {
		return
	}
	resp, err := h.Module.Friends.Relationship(c, space, req)
	respondJSON(c, resp, err)
}

func (h *Handlers) RefreshFriendShares(c *gin.Context, space *spacerepo.SpaceRecord) {
	var req models.RefreshFriendSharesRequest
	if !bindJSON(c, &req) {
		return
	}
	respondStatus(c, h.Module.Friends.RefreshShares(c, space, req))
}

func (h *Handlers) ListFriendShares(c *gin.Context, space *spacerepo.SpaceRecord) {
	resp, err := h.Module.Friends.ListShares(c, space)
	respondJSON(c, resp, err)
}
