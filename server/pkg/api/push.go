package api

import (
	"net/http"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

type PushHandler struct {
	PushController *controller.PushController
}

func (h *PushHandler) AddToken(c *gin.Context) {
	platform := "ios"
	req := ente.PushTokenRequest{Platform: &platform}
	err := handler.BindJSON(c, &req)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	sessionHash := auth.HashToken(auth.GetToken(c))
	err = h.PushController.AddToken(auth.GetUserID(c.Request.Header), sessionHash[:], req)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}
