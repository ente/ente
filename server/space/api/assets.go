package api

import (
	"github.com/ente/museum/space/models"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/gin-gonic/gin"
)

func (h *Handlers) PresignUpload(c *gin.Context, space *spacerepo.SpaceRecord) {
	var req models.PresignUploadRequest
	if !bindJSON(c, &req) {
		return
	}
	resp, err := h.Module.Assets.PresignUpload(c, space, req)
	respondJSON(c, resp, err)
}

func (h *Handlers) AssetRedirect(c *gin.Context) {
	var req models.AssetRedirectRequest
	if !bindQuery(c, &req) {
		return
	}
	req.SpaceID = c.Param("spaceID")
	resp, err := h.Module.Assets.Redirect(c, req)
	respondJSON(c, resp, err)
}
