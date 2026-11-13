package api

import (
	"net/http"
	"strconv"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

type TrashHandler struct {
	Controller *controller.TrashController
}

func (t *TrashHandler) GetDiffV2(c *gin.Context) {
	enteApp := auth.GetApp(c)

	userID := auth.GetUserID(c.Request.Header)
	sinceTime, _ := strconv.ParseInt(c.Query("sinceTime"), 10, 64)
	diff, hasMore, err := t.Controller.GetDiff(userID, sinceTime, enteApp)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"diff":    diff,
		"hasMore": hasMore,
	})
}

func (t *TrashHandler) Delete(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	var request ente.DeleteTrashFilesRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	request.OwnerID = userID
	err := t.Controller.Delete(c.Request.Context(), request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

func (t *TrashHandler) Empty(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	enteApp := auth.GetApp(c)
	var request ente.EmptyTrashRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	err := t.Controller.EmptyTrash(c, userID, request, enteApp)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}
