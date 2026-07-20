package api

import (
	"database/sql"
	"net/http"

	"github.com/ente/museum/space/models"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

func (h *Handlers) ListSpaces(c *gin.Context) {
	resp, err := h.Module.Spaces.List(c)
	respondJSON(c, resp, err)
}

func (h *Handlers) CreateSpace(c *gin.Context) {
	var req models.CreateSpaceRequest
	if !bindJSON(c, &req) {
		return
	}
	resp, err := h.Module.Spaces.Create(c, req)
	respondJSON(c, resp, err)
}

func (h *Handlers) GetSpaceProfile(c *gin.Context) {
	var req models.GetSpaceProfileRequest
	if !bindQuery(c, &req) {
		return
	}
	req.SpaceID = c.Param("spaceID")
	resp, err := h.Module.Spaces.GetProfile(c, req)
	respondJSON(c, resp, err)
}

func (h *Handlers) UpdateSpaceProfile(c *gin.Context, space *spacerepo.SpaceRecord) {
	var req models.UpdateSpaceProfileRequest
	if !bindJSON(c, &req) {
		return
	}
	resp, err := h.Module.Spaces.UpdateProfile(c, space, req)
	respondJSON(c, resp, err)
}

func (h *Handlers) UpdateSpaceSlug(c *gin.Context, space *spacerepo.SpaceRecord) {
	var req models.UpdateSpaceSlugRequest
	if !bindJSON(c, &req) {
		return
	}
	resp, err := h.Module.Spaces.UpdateSlug(c, space, req)
	respondJSON(c, resp, err)
}

func (h *Handlers) LookupSpaceBySlug(c *gin.Context) {
	resp, err := h.Module.Spaces.LookupBySlug(c, c.Param("spaceSlug"))
	if err != nil && stacktrace.RootCause(err) == sql.ErrNoRows {
		c.Status(http.StatusNotFound)
		return
	}
	respondJSON(c, resp, err)
}

func (h *Handlers) SpaceSlugAvailability(c *gin.Context) {
	resp, err := h.Module.Spaces.SlugAvailability(c, c.Param("spaceSlug"))
	respondJSON(c, resp, err)
}

func (h *Handlers) RotateSpaceKey(c *gin.Context, space *spacerepo.SpaceRecord) {
	var req models.RotateSpaceKeyRequest
	if !bindJSON(c, &req) {
		return
	}
	resp, err := h.Module.Spaces.RotateKey(c, space, req)
	respondJSON(c, resp, err)
}

func (h *Handlers) ListSpaceKeyVersions(c *gin.Context) {
	var req models.GetSpaceProfileRequest
	if !bindQuery(c, &req) {
		return
	}
	req.SpaceID = c.Param("spaceID")
	resp, err := h.Module.Spaces.ListVersions(c, req)
	respondJSON(c, resp, err)
}
