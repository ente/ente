package api

import (
	"net/http"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller/public"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

// PublicCommentsHandler handles public collection social APIs.
type PublicCommentsHandler struct {
	CommentsCtrl     *public.CommentsController
	ReactionsCtrl    *public.ReactionsController
	AnonIdentityCtrl *public.AnonIdentityController
}

const (
	maxPublicCommentCipherSize  = 20 * 1024
	maxPublicReactionCipherSize = 2 * 1024
)

type publicCommentPayload struct {
	ID              string  `json:"id"`
	FileID          *int64  `json:"fileID"`
	ParentCommentID *string `json:"parentCommentID"`
	Cipher          string  `json:"cipher" binding:"required"`
	Nonce           string  `json:"nonce" binding:"required"`
	AnonUserID      *string `json:"anonUserID"`
	AnonToken       string  `json:"anonToken"`
}

type publicCommentEditPayload struct {
	Cipher     string  `json:"cipher" binding:"required"`
	Nonce      string  `json:"nonce" binding:"required"`
	AnonUserID *string `json:"anonUserID"`
	AnonToken  string  `json:"anonToken"`
}

type publicAnonPayload struct {
	AnonUserID *string `json:"anonUserID"`
	AnonToken  string  `json:"anonToken"`
}

type publicReactionPayload struct {
	ID         string  `json:"id"`
	FileID     *int64  `json:"fileID"`
	CommentID  *string `json:"commentID"`
	Cipher     string  `json:"cipher" binding:"required"`
	Nonce      string  `json:"nonce" binding:"required"`
	AnonUserID *string `json:"anonUserID"`
	AnonToken  string  `json:"anonToken"`
}

type publicReactionDeletePayload struct {
	AnonUserID *string `json:"anonUserID"`
	AnonToken  string  `json:"anonToken"`
}

type publicAnonIdentityPayload struct {
	Cipher string `json:"cipher" binding:"required"`
	Nonce  string `json:"nonce" binding:"required"`
}

func (h *PublicCommentsHandler) CreateComment(c *gin.Context) {
	var payload publicCommentPayload
	if err := handler.BindJSON(c, &payload); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	if !ensurePublicCommentsEnabled(c) {
		return
	}
	if len(payload.Cipher) == 0 || len(payload.Cipher) > maxPublicCommentCipherSize || len(payload.Nonce) == 0 {
		handler.Error(c, ente.ErrBadRequest)
		return
	}
	collectionID := auth.MustGetPublicAccessContext(c).CollectionID
	controllerReq := public.CommentRequest{
		ID:              payload.ID,
		FileID:          payload.FileID,
		ParentCommentID: payload.ParentCommentID,
		Cipher:          payload.Cipher,
		Nonce:           payload.Nonce,
		AnonUserID:      payload.AnonUserID,
		AnonToken:       payload.AnonToken,
	}
	id, err := h.CommentsCtrl.CreateComment(c, collectionID, controllerReq)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusCreated, gin.H{"id": id})
}

func (h *PublicCommentsHandler) UpdateComment(c *gin.Context) {
	var payload publicCommentEditPayload
	if err := handler.BindJSON(c, &payload); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	if !ensurePublicCommentsEnabled(c) {
		return
	}
	if len(payload.Cipher) == 0 || len(payload.Cipher) > maxPublicCommentCipherSize || len(payload.Nonce) == 0 {
		handler.Error(c, ente.ErrBadRequest)
		return
	}
	collectionID := auth.MustGetPublicAccessContext(c).CollectionID
	commentID := c.Param("commentID")
	if commentID == "" {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "missing commentID"))
		return
	}
	controllerReq := public.CommentUpdateRequest{
		Cipher:     payload.Cipher,
		Nonce:      payload.Nonce,
		AnonUserID: payload.AnonUserID,
		AnonToken:  payload.AnonToken,
	}
	if err := h.CommentsCtrl.UpdateComment(c, collectionID, commentID, controllerReq); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

func (h *PublicCommentsHandler) DeleteComment(c *gin.Context) {
	var payload publicAnonPayload
	if err := handler.BindJSON(c, &payload); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	if !ensurePublicCommentsEnabled(c) {
		return
	}
	collectionID := auth.MustGetPublicAccessContext(c).CollectionID
	commentID := c.Param("commentID")
	if commentID == "" {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "missing commentID"))
		return
	}
	controllerReq := public.CommentDeleteRequest{
		AnonUserID: payload.AnonUserID,
		AnonToken:  payload.AnonToken,
	}
	if err := h.CommentsCtrl.DeleteComment(c, collectionID, commentID, controllerReq); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

func (h *PublicCommentsHandler) CommentDiff(c *gin.Context) {
	if !ensurePublicCommentsEnabled(c) {
		return
	}
	collectionID := auth.MustGetPublicAccessContext(c).CollectionID
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
	comments, hasMore, err := h.CommentsCtrl.ListComments(c, collectionID, since, limit, fileID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{"comments": comments, "hasMore": hasMore})
}

func (h *PublicCommentsHandler) CreateReaction(c *gin.Context) {
	var payload publicReactionPayload
	if err := handler.BindJSON(c, &payload); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	if !ensurePublicCommentsEnabled(c) {
		return
	}
	if len(payload.Cipher) == 0 || len(payload.Cipher) > maxPublicReactionCipherSize || len(payload.Nonce) == 0 {
		handler.Error(c, ente.ErrBadRequest)
		return
	}
	collectionID := auth.MustGetPublicAccessContext(c).CollectionID
	controllerReq := public.ReactionRequest{
		ID:         payload.ID,
		FileID:     payload.FileID,
		CommentID:  payload.CommentID,
		Cipher:     payload.Cipher,
		Nonce:      payload.Nonce,
		AnonUserID: payload.AnonUserID,
		AnonToken:  payload.AnonToken,
	}
	id, err := h.ReactionsCtrl.UpsertReaction(c, collectionID, controllerReq)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{"id": id})
}

func (h *PublicCommentsHandler) ReactionDiff(c *gin.Context) {
	if !ensurePublicCommentsEnabled(c) {
		return
	}
	collectionID := auth.MustGetPublicAccessContext(c).CollectionID
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
	commentIDRaw := c.Query("commentID")
	var commentID *string
	if commentIDRaw != "" {
		commentID = &commentIDRaw
	}
	reactions, hasMore, err := h.ReactionsCtrl.ListReactions(c, collectionID, since, limit, fileID, commentID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{"reactions": reactions, "hasMore": hasMore})
}

func (h *PublicCommentsHandler) DeleteReaction(c *gin.Context) {
	var payload publicReactionDeletePayload
	if err := handler.BindJSON(c, &payload); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	if !ensurePublicCommentsEnabled(c) {
		return
	}
	collectionID := auth.MustGetPublicAccessContext(c).CollectionID
	reactionID := c.Param("reactionID")
	if reactionID == "" {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "missing reactionID"))
		return
	}
	controllerReq := public.ReactionDeleteRequest{
		AnonUserID: payload.AnonUserID,
		AnonToken:  payload.AnonToken,
	}
	if err := h.ReactionsCtrl.DeleteReaction(c, collectionID, reactionID, controllerReq); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

func (h *PublicCommentsHandler) Participants(c *gin.Context) {
	if !ensurePublicCommentsEnabled(c) {
		return
	}
	collectionID := auth.MustGetPublicAccessContext(c).CollectionID
	// ignore includeSharees flag for now
	participants, err := h.CommentsCtrl.Participants(c, collectionID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{"participants": participants})
}

func (h *PublicCommentsHandler) CreateAnonIdentity(c *gin.Context) {
	var payload publicAnonIdentityPayload
	if err := handler.BindJSON(c, &payload); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	if !ensurePublicCommentsEnabled(c) {
		return
	}
	if len(payload.Cipher) == 0 || len(payload.Nonce) == 0 {
		handler.Error(c, ente.ErrBadRequest)
		return
	}
	collectionID := auth.MustGetPublicAccessContext(c).CollectionID
	resp, err := h.AnonIdentityCtrl.Create(c, public.CreateAnonIdentityRequest{
		CollectionID: collectionID,
		Cipher:       payload.Cipher,
		Nonce:        payload.Nonce,
	})
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusCreated, resp)
}

func (h *PublicCommentsHandler) AnonProfiles(c *gin.Context) {
	if !ensurePublicCommentsEnabled(c) {
		return
	}
	collectionID := auth.MustGetPublicAccessContext(c).CollectionID
	profiles, err := h.CommentsCtrl.ListAnonProfiles(c, collectionID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{"profiles": profiles})
}

// SocialDiff returns both comments and reactions in a single response.
func (h *PublicCommentsHandler) SocialDiff(c *gin.Context) {
	if !ensurePublicCommentsEnabled(c) {
		return
	}
	collectionID := auth.MustGetPublicAccessContext(c).CollectionID
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

	comments, hasMoreComments, err := h.CommentsCtrl.ListComments(c, collectionID, since, limit, fileID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}

	reactions, hasMoreReactions, err := h.ReactionsCtrl.ListReactions(c, collectionID, since, limit, fileID, nil)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"comments":         comments,
		"reactions":        reactions,
		"hasMoreComments":  hasMoreComments,
		"hasMoreReactions": hasMoreReactions,
	})
}

func ensurePublicCommentsEnabled(c *gin.Context) bool {
	if auth.MustGetPublicAccessContext(c).EnableComment {
		return true
	}
	handler.Error(c, &ente.ErrPublicCommentDisabled)
	return false
}
