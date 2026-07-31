package api

import (
	"github.com/ente/museum/space/models"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/gin-gonic/gin"
)

func (h *Handlers) GetSpaceLink(c *gin.Context, space *spacerepo.SpaceRecord) {
	resp, err := h.Module.Links.Get(c, space)
	respondJSON(c, resp, err)
}

func (h *Handlers) CreateSpaceLink(c *gin.Context, space *spacerepo.SpaceRecord) {
	var req models.SpaceLinkWriteRequest
	if !bindJSON(c, &req) {
		return
	}
	resp, err := h.Module.Links.Create(c, space, req)
	respondJSON(c, resp, err)
}

func (h *Handlers) RotateSpaceLink(c *gin.Context, space *spacerepo.SpaceRecord) {
	var req models.SpaceLinkWriteRequest
	if !bindJSON(c, &req) {
		return
	}
	resp, err := h.Module.Links.Rotate(c, space, req)
	respondJSON(c, resp, err)
}

func (h *Handlers) SpaceLinkBootstrap(c *gin.Context) {
	resp, err := h.Module.Links.Bootstrap(c, c.Param("spaceSlug"))
	respondJSON(c, resp, err)
}

func (h *Handlers) SpaceLinkProfile(c *gin.Context) {
	resp, err := h.Module.Links.Profile(c, c.Param("spaceSlug"))
	respondJSON(c, resp, err)
}

func (h *Handlers) SpaceLinkPosts(c *gin.Context) {
	resp, err := h.Module.Links.RecentPosts(c, c.Param("spaceSlug"))
	respondJSON(c, resp, err)
}

func (h *Handlers) SpaceLinkVersions(c *gin.Context) {
	resp, err := h.Module.Links.Versions(c, c.Param("spaceSlug"))
	respondJSON(c, resp, err)
}

func (h *Handlers) SpaceLinkAssetRedirect(c *gin.Context) {
	var req models.AssetRedirectRequest
	if !bindQuery(c, &req) {
		return
	}
	resp, err := h.Module.Links.AssetRedirect(c, c.Param("spaceSlug"), req)
	respondJSON(c, resp, err)
}
