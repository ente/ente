package api

import (
	"net/http"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/gin-gonic/gin"
)

func (h *CollectionHandler) AcceptInvitations(c *gin.Context) {
	var request ente.AcceptCollectionInvitationsRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, err)
		return
	}
	response, err := h.Controller.AcceptInvitations(c, request)
	if err != nil {
		handler.Error(c, err)
		return
	}
	c.JSON(http.StatusOK, response)
}

func (h *CollectionHandler) RejectInvitation(c *gin.Context) {
	var request ente.RejectCollectionInvitationRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, err)
		return
	}
	if err := h.Controller.RejectInvitation(c, request); err != nil {
		handler.Error(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}
