package api

import (
	"github.com/ente/museum/space/models"
	"github.com/ente/museum/space/repo"
	"github.com/gin-gonic/gin"
)

func (h *Handlers) CreatePoke(c *gin.Context, space *repo.SpaceRecord) {
	var req models.CreatePokeRequest
	if !bindJSON(c, &req) {
		return
	}
	friendSpaceID, ok := stringParam(c, "friendSpaceID")
	if !ok {
		return
	}
	respondStatus(c, h.Module.Pokes.Create(c, space, friendSpaceID, req))
}
