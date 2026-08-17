package api

import (
	"net/http"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller/remotestore"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

type RemoteStoreHandler struct {
	Controller *remotestore.Controller
}

func (h *RemoteStoreHandler) InsertOrUpdate(c *gin.Context) {
	var request ente.UpdateKeyValueRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Request binding failed"))
		return
	}

	err := h.Controller.InsertOrUpdate(c, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to update key's value"))
		return
	}
	c.Status(http.StatusOK)
}

func (h *RemoteStoreHandler) RemoveKey(c *gin.Context) {
	key := c.Param("key")
	if key == "" {
		handler.Error(c, stacktrace.Propagate(ente.NewBadRequestWithMessage("key is missing"), ""))
		return
	}
	err := h.Controller.RemoveKey(c, key)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to update key's value"))
		return
	}
	c.Status(http.StatusOK)
}

func (h *RemoteStoreHandler) GetKey(c *gin.Context) {
	var request ente.GetValueRequest
	if err := c.ShouldBindQuery(&request); err != nil {
		handler.Error(c,
			stacktrace.Propagate(ente.ErrBadRequest, "Request binding failed %s", err))
		return
	}

	resp, err := h.Controller.Get(c, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to get key value"))
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *RemoteStoreHandler) GetFeatureFlags(c *gin.Context) {
	resp, err := h.Controller.GetFeatureFlags(c)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to get feature flags"))
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *RemoteStoreHandler) CheckDomain(c *gin.Context) {
	domain := c.Query("domain")
	if domain == "" {
		handler.Error(c, stacktrace.Propagate(ente.NewBadRequestWithMessage("domain is missing"), ""))
		return
	}
	if err := ente.ValidatePublicCustomDomain(domain); err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	_, err := h.Controller.DomainOwner(c, domain)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to check custom domain"))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}
