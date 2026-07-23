package api

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/ente/museum/ente"
	entity "github.com/ente/museum/ente/cast"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/controller/cast"
	"github.com/ente/museum/pkg/controller/collections"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// CastHandler exposes request handlers for publicly accessible collections
type CastHandler struct {
	FileCtrl       *controller.FileController
	CollectionCtrl *collections.CollectionController
	Ctrl           *cast.Controller
}

func (h *CastHandler) RegisterDevice(c *gin.Context) {
	var request entity.RegisterDeviceRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to bind"))
		return
	}
	code, err := h.Ctrl.RegisterDevice(c, &request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to register device"))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"deviceCode": code,
	})
}

func (h *CastHandler) GetDeviceInfo(c *gin.Context) {
	deviceCode := getDeviceCode(c)
	publicKey, err := h.Ctrl.GetPublicKey(c, deviceCode)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to get public key"))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"publicKey": publicKey,
	})
}

func (h *CastHandler) GetAllDevices(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	devices, err := h.Ctrl.GetAllDevices(c, userID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to get devices"))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"devices": devices,
	})
}

func (h *CastHandler) DeleteDevice(c *gin.Context) {
	deviceID, err := uuid.Parse(c.Param("deviceID"))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "failed to parse device id"))
		return
	}
	userID := auth.GetUserID(c.Request.Header)
	if err := h.Ctrl.DeleteDevice(
		c,
		userID,
		deviceID,
	); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to delete device"))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

func (h *CastHandler) InsertCastData(c *gin.Context) {
	var request entity.CastRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to bind"))
		return
	}
	err := h.Ctrl.InsertCastData(c, &request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to start cast"))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

// RevokeAllToken disable all active cast token for a user
func (h *CastHandler) RevokeAllToken(c *gin.Context) {
	err := h.Ctrl.RevokeAllToken(c)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to start cast"))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

func (h *CastHandler) GetCastData(c *gin.Context) {
	deviceCode := getDeviceCode(c)
	encCastData, err := h.Ctrl.GetEncCastData(c, deviceCode)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to get encrypted payload"))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"encCastData": encCastData,
	})

}

// GetFile redirects the request to the file location
func (h *CastHandler) GetFile(c *gin.Context) {
	h.getFileForType(c, ente.FILE)
}

// GetThumbnail redirects the request to the file's thumbnail location
func (h *CastHandler) GetThumbnail(c *gin.Context) {
	h.getFileForType(c, ente.THUMBNAIL)
}

// GetCollection redirects the request to the collection location
func (h *CastHandler) GetCollection(c *gin.Context) {
	collection, err := h.CollectionCtrl.GetCastCollection(c)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"collection": collection,
	})
}

// GetDiff returns the diff within a collection since a timestamp
func (h *CastHandler) GetDiff(c *gin.Context) {
	sinceTime, err := strconv.ParseInt(c.Query("sinceTime"), 10, 64)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	files, hasMore, err := h.CollectionCtrl.GetCastDiff(c, sinceTime)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"diff":    files,
		"hasMore": hasMore,
	})
}

func getDeviceCode(c *gin.Context) string {
	return strings.ToUpper(c.Param("deviceCode"))
}

func (h *CastHandler) getFileForType(c *gin.Context, objectType ente.ObjectType) {
	fileID, err := strconv.ParseInt(c.Param("fileID"), 10, 64)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, ""))
		return
	}
	castCtx := auth.GetCastCtx(c)
	url, err := h.FileCtrl.GetPublicOrCastFileURL(c, fileID, objectType, castCtx.CollectionID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Redirect(http.StatusTemporaryRedirect, url)
}
