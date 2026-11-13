package api

import (
	"net/http"

	"github.com/ente/museum/ente"
	public "github.com/ente/museum/pkg/controller/public"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

type PasteHandler struct {
	Controller *public.PasteController
}

func (h *PasteHandler) Create(c *gin.Context) {
	var req ente.CreatePasteRequest
	if err := handler.BindJSON(c, &req); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "invalid request"))
		return
	}

	resp, err := h.Controller.Create(c, &req)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to create paste"))
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *PasteHandler) Guard(c *gin.Context) {
	var req ente.PasteTokenRequest
	if err := handler.BindJSON(c, &req); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "invalid request"))
		return
	}
	if err := h.Controller.SetGuard(c, &req); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to set paste guard"))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

func (h *PasteHandler) Consume(c *gin.Context) {
	var req ente.PasteTokenRequest
	if err := handler.BindJSON(c, &req); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "invalid request"))
		return
	}
	resp, err := h.Controller.Consume(c, &req)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to consume paste"))
		return
	}
	c.JSON(http.StatusOK, resp)
}
