package api

import (
	"net/http"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type EventHandler struct {
	Repo *repo.EventRepository
}

func (h *EventHandler) Create(c *gin.Context) {
	request, ok := bindEventRequest(c)
	if !ok {
		return
	}
	if request.Event != ente.EventInstall {
		handler.Error(c, ente.NewBadRequestWithMessage("invalid event"))
		return
	}
	data := enrichEventData(c, request.Data)
	if err := h.Repo.Insert(c, request.ID, request.Event, request.App, request.Platform, data, nil); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to create event"))
		return
	}
	c.Status(http.StatusOK)
}

func (h *EventHandler) CreateForUser(c *gin.Context) {
	request, ok := bindEventRequest(c)
	if !ok {
		return
	}
	if request.Event != ente.EventSignUp && request.Event != ente.EventLogIn {
		handler.Error(c, ente.NewBadRequestWithMessage("invalid event"))
		return
	}
	userID := auth.GetUserID(c.Request.Header)
	installData, found, err := h.Repo.GetData(c, request.ID, ente.EventInstall)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to read install event"))
		return
	}
	data := map[string]interface{}{}
	if found {
		data = installData
	}
	for key, value := range request.Data {
		data[key] = value
	}
	data = enrichEventData(c, data)
	if err := h.Repo.Insert(c, request.ID, request.Event, request.App, request.Platform, data, &userID); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to create user event"))
		return
	}
	c.Status(http.StatusOK)
}

func bindEventRequest(c *gin.Context) (ente.EventRequest, bool) {
	var request ente.EventRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "request binding failed"))
		return request, false
	}
	if _, err := uuid.Parse(request.ID); err != nil {
		handler.Error(c, ente.NewBadRequestWithMessage("invalid id"))
		return request, false
	}
	if request.Data == nil {
		handler.Error(c, ente.NewBadRequestWithMessage("data is required"))
		return request, false
	}
	return request, true
}

func enrichEventData(c *gin.Context, data map[string]interface{}) map[string]interface{} {
	delete(data, "app")
	delete(data, "platform")
	version := c.GetHeader("X-Client-Version")
	if version != "" {
		data["app_version"] = version
	}
	return data
}
