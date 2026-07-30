package api

import (
	"fmt"
	"net/http"
	"strconv"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

type CollectionActionsHandler struct {
	Controller *controller.CollectionActionsController
}

const collectionActionsLimit = 2000

// ListPendingRemove returns pending REMOVE actions after the provided updatedAt timestamp
func (h *CollectionActionsHandler) ListPendingRemove(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	updatedAfter, err := parseSinceTime(c.Query("sinceTime"))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	actions, err := h.Controller.ListPendingRemoveActions(c, userID, updatedAfter, collectionActionsLimit)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"actions": actions,
		"hasMore": len(actions) >= collectionActionsLimit,
	})
}

// ListDeleteSuggestions returns pending DELETE_SUGGESTED actions for the actor.
func (h *CollectionActionsHandler) ListDeleteSuggestions(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	updatedAfter, err := parseSinceTime(c.Query("sinceTime"))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	actions, err := h.Controller.ListPendingDeleteSuggestions(c, userID, updatedAfter, collectionActionsLimit)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"actions": actions,
		"hasMore": len(actions) >= collectionActionsLimit,
	})
}

type rejectDeleteSuggestionsRequest struct {
	FileIDs []int64 `json:"fileIDs" binding:"required"`
}

// RejectDeleteSuggestions clears pending DELETE_SUGGESTED actions for the provided file IDs.
func (h *CollectionActionsHandler) RejectDeleteSuggestions(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	var req rejectDeleteSuggestionsRequest
	if err := handler.BindJSON(c, &req); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "invalid payload"))
		return
	}
	if len(req.FileIDs) == 0 {
		handler.Error(c, stacktrace.Propagate(ente.NewBadRequestWithMessage("fileIDs must not be empty"), ""))
		return
	}
	if len(req.FileIDs) > collectionActionsLimit {
		handler.Error(c, stacktrace.Propagate(ente.NewBadRequestWithMessage(fmt.Sprintf("can not reject more than %d items in one request", collectionActionsLimit)), ""))
		return
	}
	updated, err := h.Controller.RejectDeleteSuggestions(c, userID, req.FileIDs)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to reject delete suggestions"))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"updated": updated,
	})
}

func parseSinceTime(raw string) (int64, error) {
	if raw == "" {
		return 0, nil
	}
	return strconv.ParseInt(raw, 10, 64)
}
