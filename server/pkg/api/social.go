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

// SocialHandler exposes unified diff and counts endpoints.
type SocialHandler struct {
	Controller *social.Controller
}

func (h *SocialHandler) UnifiedDiff(c *gin.Context) {
	collectionID, err := strconv.ParseInt(c.Query("collectionID"), 10, 64)
	if err != nil || collectionID <= 0 {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "invalid collectionID"))
		return
	}
	baseSinceRaw := c.Query("sinceTime")
	baseSince, err := parseDiffSinceTime(baseSinceRaw)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	commentsSinceRaw := c.Query("commentsSinceTime")
	commentsSince, err := parseDiffSinceTime(commentsSinceRaw)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	if commentsSinceRaw == "" {
		commentsSince = baseSince
	}
	reactionsSinceRaw := c.Query("reactionsSinceTime")
	reactionsSince, err := parseDiffSinceTime(reactionsSinceRaw)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	if reactionsSinceRaw == "" {
		reactionsSince = baseSince
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
	req := social.UnifiedDiffRequest{
		Actor:          social.Actor{UserID: &userID},
		CollectionID:   collectionID,
		CommentsSince:  commentsSince,
		ReactionsSince: reactionsSince,
		Limit:          limit,
		FileID:         fileID,
		RequireAccess:  true,
	}
	comments, reactions, hasMoreComments, hasMoreReactions, err := h.Controller.UnifiedDiff(c, req)
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

func (h *SocialHandler) Counts(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	if userID <= 0 {
		handler.Error(c, ente.ErrAuthenticationRequired)
		return
	}
	counts, err := h.Controller.CountActiveCollections(c, userID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{"counts": counts})
}

func (h *SocialHandler) LatestUpdates(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	if userID <= 0 {
		handler.Error(c, ente.ErrAuthenticationRequired)
		return
	}
	app := auth.GetApp(c)
	updates, err := h.Controller.LatestUpdates(c, userID, app)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{"updates": updates})
}

func (h *SocialHandler) AnonProfiles(c *gin.Context) {
	collectionID, err := strconv.ParseInt(c.Query("collectionID"), 10, 64)
	if err != nil || collectionID <= 0 {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "invalid collectionID"))
		return
	}
	userID := auth.GetUserID(c.Request.Header)
	if userID <= 0 {
		handler.Error(c, ente.ErrAuthenticationRequired)
		return
	}
	profiles, err := h.Controller.ListAnonProfiles(c, social.AnonProfilesRequest{
		Actor:         social.Actor{UserID: &userID},
		CollectionID:  collectionID,
		RequireAccess: true,
	})
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{"profiles": profiles})
}
