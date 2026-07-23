package api

import (
	"net/http"
	"time"

	"github.com/ente/museum/ente"
	model "github.com/ente/museum/ente/authenticator"
	authenticaor "github.com/ente/museum/pkg/controller/authenticator"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// AuthenticatorHandler expose request handlers authenticator related endpoints
type AuthenticatorHandler struct {
	Controller *authenticaor.Controller
}

// CreateKey...
func (h *AuthenticatorHandler) CreateKey(c *gin.Context) {
	var request model.CreateKeyRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Request binding failed"))
		return
	}
	err := h.Controller.CreateKey(c, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Failed to create CreateKey"))
		return
	}
	c.Status(http.StatusOK)
}

// GetKey...
func (h *AuthenticatorHandler) GetKey(c *gin.Context) {
	resp, err := h.Controller.GetKey(c)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to getKey"))
		return
	}
	c.JSON(http.StatusOK, resp)
}

// CreateEntity...
func (h *AuthenticatorHandler) CreateEntity(c *gin.Context) {
	var request model.CreateEntityRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Request binding failed"))
		return
	}
	resp, err := h.Controller.CreateEntity(c, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Failed to create CreateEntity"))
		return
	}
	c.JSON(http.StatusOK, resp)
}

// UpdateEntity...
func (h *AuthenticatorHandler) UpdateEntity(c *gin.Context) {
	var request model.UpdateEntityRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Request binding failed"))
		return
	}
	err := h.Controller.UpdateEntity(c, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Failed to update UpdateEntity"))
		return
	}
	c.Status(http.StatusOK)
}

// DeleteEntity...
func (h *AuthenticatorHandler) DeleteEntity(c *gin.Context) {
	id, err := uuid.Parse(c.Query("id"))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "failed to find id"))
		return
	}
	_, err = h.Controller.Delete(c, id)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Failed to delete DeleteEntity"))
		return
	}
	c.Status(http.StatusOK)
}

// GetDiff...
func (h *AuthenticatorHandler) GetDiff(c *gin.Context) {
	var request model.GetEntityDiffRequest
	if err := c.ShouldBindQuery(&request); err != nil {
		handler.Error(c,
			stacktrace.Propagate(ente.ErrBadRequest, "Request binding failed %s", err))
		return
	}

	entities, err := h.Controller.GetDiff(c, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Failed to fetch authenticator entity diff"))
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"diff":      entities,
		"timestamp": time.Now().UnixMicro(),
	})
}
