package api

import (
	"github.com/ente/museum/space/models"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/gin-gonic/gin"
)

func (h *Handlers) CreatePost(c *gin.Context, space *spacerepo.SpaceRecord) {
	var req models.CreatePostRequest
	if !bindJSON(c, &req) {
		return
	}
	resp, err := h.Module.Posts.Create(c, space, req)
	respondJSON(c, resp, err)
}

func (h *Handlers) ListFeed(c *gin.Context, space *spacerepo.SpaceRecord) {
	var req models.ListFeedRequest
	if !bindQuery(c, &req) {
		return
	}
	resp, err := h.Module.Posts.ListFeed(c, space, req)
	respondJSON(c, resp, err)
}

func (h *Handlers) ListPosts(c *gin.Context) {
	var req models.ListPostsRequest
	if !bindQuery(c, &req) {
		return
	}
	req.SpaceID = c.Param("spaceID")
	resp, err := h.Module.Posts.List(c, req)
	respondJSON(c, resp, err)
}

func (h *Handlers) GetPost(c *gin.Context) {
	var req models.GetPostRequest
	if !bindQuery(c, &req) {
		return
	}
	req.SpaceID = c.Param("spaceID")
	postID, ok := positiveInt64Param(c, "postID")
	if !ok {
		return
	}
	resp, err := h.Module.Posts.Get(c, postID, req)
	respondJSON(c, resp, err)
}

func (h *Handlers) UpdatePostCaption(c *gin.Context, space *spacerepo.SpaceRecord) {
	var req models.UpdatePostCaptionRequest
	if !bindJSON(c, &req) {
		return
	}
	postID, ok := positiveInt64Param(c, "postID")
	if !ok {
		return
	}
	resp, err := h.Module.Posts.UpdateCaption(c, space, postID, req)
	respondJSON(c, resp, err)
}

func (h *Handlers) LikePost(c *gin.Context, space *spacerepo.SpaceRecord) {
	h.setPostLike(c, space, true)
}

func (h *Handlers) UnlikePost(c *gin.Context, space *spacerepo.SpaceRecord) {
	h.setPostLike(c, space, false)
}

func (h *Handlers) setPostLike(c *gin.Context, space *spacerepo.SpaceRecord, like bool) {
	postID, ok := positiveInt64Param(c, "postID")
	if !ok {
		return
	}
	resp, err := h.Module.Posts.SetLike(c, space, postID, like)
	respondJSON(c, resp, err)
}

func (h *Handlers) DeletePost(c *gin.Context, space *spacerepo.SpaceRecord) {
	postID, ok := positiveInt64Param(c, "postID")
	if !ok {
		return
	}
	respondStatus(c, h.Module.Posts.Delete(c, space, postID))
}
