package api

import (
	"net/http"
	"strconv"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller/social"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

const maxCommentPayloadBytes = 20 * 1024

// CommentsHandler exposes authenticated comment APIs.
type CommentsHandler struct {
	Controller *social.CommentsController
}

type createCommentPayload struct {
	ID              string  `json:"id"`
	CollectionID    int64   `json:"collectionID" binding:"required"`
	FileID          *int64  `json:"fileID"`
	ParentCommentID *string `json:"parentCommentID"`
	Cipher          string  `json:"cipher" binding:"required"`
	Nonce           string  `json:"nonce" binding:"required"`
}

type updateCommentPayload struct {
	Cipher string `json:"cipher" binding:"required"`
	Nonce  string `json:"nonce" binding:"required"`
}

func (h *CommentsHandler) Create(c *gin.Context) {
	var payload createCommentPayload
	if err := handler.BindJSON(c, &payload); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	if len(payload.Cipher) == 0 || len(payload.Cipher) > maxCommentPayloadBytes || len(payload.Nonce) == 0 {
		handler.Error(c, ente.ErrBadRequest)
		return
	}
	userID := auth.GetUserID(c.Request.Header)
	if userID <= 0 {
		handler.Error(c, ente.ErrAuthenticationRequired)
		return
	}
	req := social.CreateCommentRequest{
		Actor:           social.Actor{UserID: &userID},
		CollectionID:    payload.CollectionID,
		FileID:          payload.FileID,
		ParentCommentID: payload.ParentCommentID,
		Cipher:          payload.Cipher,
		Nonce:           payload.Nonce,
		ID:              payload.ID,
		RequireAccess:   true,
	}
	id, err := h.Controller.Create(c, req)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusCreated, gin.H{"id": id})
}

func (h *CommentsHandler) Diff(c *gin.Context) {
	collectionID, err := strconv.ParseInt(c.Query("collectionID"), 10, 64)
	if err != nil || collectionID <= 0 {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "invalid collectionID"))
		return
	}
	since, err := parseDiffSinceTime(c.Query("sinceTime"))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	limit, err := parseDiffLimit(c.Query("limit"))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	fileID, err := parseOptionalInt64(c.Query("fileID"))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	userID := auth.GetUserID(c.Request.Header)
	if userID <= 0 {
		handler.Error(c, ente.ErrAuthenticationRequired)
		return
	}
	req := social.CommentDiffRequest{
		Actor:         social.Actor{UserID: &userID},
		CollectionID:  collectionID,
		Since:         since,
		Limit:         limit,
		FileID:        fileID,
		RequireAccess: true,
	}
	comments, hasMore, err := h.Controller.Diff(c, req)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{"comments": comments, "hasMore": hasMore})
}

func (h *CommentsHandler) Update(c *gin.Context) {
	commentID := c.Param("commentID")
	if commentID == "" {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "commentID required"))
		return
	}
	var payload updateCommentPayload
	if err := handler.BindJSON(c, &payload); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	if len(payload.Cipher) == 0 || len(payload.Cipher) > maxCommentPayloadBytes || len(payload.Nonce) == 0 {
		handler.Error(c, ente.ErrBadRequest)
		return
	}
	userID := auth.GetUserID(c.Request.Header)
	if userID <= 0 {
		handler.Error(c, ente.ErrAuthenticationRequired)
		return
	}
	req := social.UpdateCommentRequest{
		Actor:         social.Actor{UserID: &userID},
		CommentID:     commentID,
		Cipher:        payload.Cipher,
		Nonce:         payload.Nonce,
		RequireAccess: true,
	}
	if err := h.Controller.UpdatePayload(c, req); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

func (h *CommentsHandler) Delete(c *gin.Context) {
	commentID := c.Param("commentID")
	if commentID == "" {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "commentID required"))
		return
	}
	userID := auth.GetUserID(c.Request.Header)
	if userID <= 0 {
		handler.Error(c, ente.ErrAuthenticationRequired)
		return
	}
	req := social.DeleteCommentRequest{
		Actor:         social.Actor{UserID: &userID},
		CommentID:     commentID,
		RequireAccess: true,
	}
	if err := h.Controller.Delete(c, req); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}
