package api

import (
	"github.com/ente/museum/space/models"
	"github.com/ente/museum/space/repo"
	"github.com/gin-gonic/gin"
)

func (h *Handlers) ListComments(c *gin.Context, space *repo.SpaceRecord) {
	id, ok := positiveInt64Param(c, "postID")
	if !ok {
		return
	}
	response, err := h.Module.Comments.List(c, space, id, c.Query("cursor"))
	respondJSON(c, response, err)
}

func (h *Handlers) CreateComment(c *gin.Context, space *repo.SpaceRecord) {
	id, ok := positiveInt64Param(c, "postID")
	if !ok {
		return
	}
	var req models.CreateCommentRequest
	if !bindJSON(c, &req) {
		return
	}
	respondStatus(c, h.Module.Comments.Create(c, space, id, req))
}

func (h *Handlers) DeleteComment(c *gin.Context, space *repo.SpaceRecord) {
	id, ok := positiveInt64Param(c, "postID")
	if !ok {
		return
	}
	respondStatus(c, h.Module.Comments.Repo.Delete(c, space.SpaceID, id, c.Param("commentID")))
}

func (h *Handlers) SetCommentReaction(c *gin.Context, space *repo.SpaceRecord) {
	id, ok := positiveInt64Param(c, "postID")
	if !ok {
		return
	}
	var req models.SetCommentReactionRequest
	if !bindJSON(c, &req) {
		return
	}
	respondStatus(c, h.Module.Comments.React(c, space, id, c.Param("commentID"), &req, ""))
}

func (h *Handlers) DeleteCommentReaction(c *gin.Context, space *repo.SpaceRecord) {
	id, ok := positiveInt64Param(c, "postID")
	if !ok {
		return
	}
	respondStatus(c, h.Module.Comments.React(c, space, id, c.Param("commentID"), nil, c.Query("actorSpaceId")))
}
