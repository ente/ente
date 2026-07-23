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

// TrashHandler handles endpoints related to trash/restore etc
type TrashHandler struct {
	Controller *controller.TrashController
}

// GetDiff returns the list of trashed files for the user that
// have changed sinceTime.
// Deprecated, shutdown when there's no traffic for 30 days
func (t *TrashHandler) GetDiff(c *gin.Context) {
	enteApp := auth.GetApp(c)

	userID := auth.GetUserID(c.Request.Header)
	sinceTime, _ := strconv.ParseInt(c.Query("sinceTime"), 10, 64)
	diff, hasMore, err := t.Controller.GetDiff(userID, sinceTime, false, enteApp)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"diff":    diff,
		"hasMore": hasMore,
	})
}

func (t *TrashHandler) GetDiffV2(c *gin.Context) {
	enteApp := auth.GetApp(c)

	userID := auth.GetUserID(c.Request.Header)
	sinceTime, _ := strconv.ParseInt(c.Query("sinceTime"), 10, 64)
	diff, hasMore, err := t.Controller.GetDiff(userID, sinceTime, true, enteApp)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"diff":    diff,
		"hasMore": hasMore,
	})
}

// Delete files permanently, queues up the file for deletion & free up the space based on file's object size
func (t *TrashHandler) Delete(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	var request ente.DeleteTrashFilesRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	request.OwnerID = userID
	err := t.Controller.Delete(c, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

// Empty deletes eligible files from the trash
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
