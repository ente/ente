package api

import (
	"net/http"
	"strconv"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller/memory_share"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

// MemoryShareHandler exposes request handlers for memory share operations
type MemoryShareHandler struct {
	Controller *memory_share.Controller
}

// Create creates a new memory share
func (h *MemoryShareHandler) Create(c *gin.Context) {
	var req ente.CreateMemoryShareRequest
	if err := handler.BindJSON(c, &req); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "invalid request body"))
		return
	}

	userID := auth.GetUserID(c.Request.Header)
	resp, err := h.Controller.Create(c, userID, req)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to create memory share"))
		return
	}

	c.JSON(http.StatusOK, resp)
}

// List returns all memory shares for the authenticated user
func (h *MemoryShareHandler) List(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	resp, err := h.Controller.List(c, userID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to list memory shares"))
		return
	}

	c.JSON(http.StatusOK, resp)
}

// Delete soft-deletes a memory share
func (h *MemoryShareHandler) Delete(c *gin.Context) {
	shareID, err := strconv.ParseInt(c.Param("shareID"), 10, 64)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "invalid share ID"))
		return
	}

	userID := auth.GetUserID(c.Request.Header)
	err = h.Controller.Delete(c, userID, shareID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to delete memory share"))
		return
	}

	c.JSON(http.StatusOK, gin.H{})
}

// GetByID returns a memory share by ID (for owner only)
func (h *MemoryShareHandler) GetByID(c *gin.Context) {
	shareID, err := strconv.ParseInt(c.Param("shareID"), 10, 64)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "invalid share ID"))
		return
	}

	userID := auth.GetUserID(c.Request.Header)
	share, err := h.Controller.GetByID(c, userID, shareID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to get memory share"))
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"memoryShare": share,
	})
}
