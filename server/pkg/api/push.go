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

// PushHandler exposes request handlers for all push related requests
type PushHandler struct {
	PushController *controller.PushController
}

func (h *PushHandler) AddToken(c *gin.Context) {
	var req ente.PushTokenRequest
	err := handler.BindJSON(c, &req)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	err = h.PushController.AddToken(auth.GetUserID(c.Request.Header), req)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}
