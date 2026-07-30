package api

import (
	"net/http"

	"github.com/ente/museum/ente"
	fileData "github.com/ente/museum/ente/filedata"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/ente/stacktrace"
	"github.com/gin-contrib/requestid"
	"github.com/gin-gonic/gin"
	"github.com/sirupsen/logrus"
)

func (h *FileHandler) PutFileData(ctx *gin.Context) {
	var req fileData.PutFileDataRequest
	if err := handler.BindJSON(ctx, &req); err != nil {
		ctx.JSON(http.StatusBadRequest, ente.NewBadRequestWithMessage(err.Error()))
		return
	}
	if err := req.Validate(); err != nil {
		ctx.JSON(http.StatusBadRequest, err)
		return
	}
	reqInt := &req
	if reqInt.Version == nil {
		version := 1
		reqInt.Version = &version
	}
	err := h.FileDataCtrl.InsertOrUpdateMetadata(ctx, &req)
	if err != nil {
		handler.Error(ctx, err)

		return
	}
	ctx.JSON(http.StatusOK, gin.H{})
}
func (h *FileHandler) PutVideoData(ctx *gin.Context) {
	var req fileData.VidPreviewRequest
	if err := handler.BindJSON(ctx, &req); err != nil {
		logrus.WithField("req_id", requestid.Get(ctx)).WithError(err).Warn("Request binding failed")
		handler.Error(ctx, ente.NewBadRequestWithMessage("invalid request body"))
		return
	}
	if err := req.Validate(); err != nil {
		ctx.JSON(http.StatusBadRequest, err)
		return
	}
	reqInt := &req
	if reqInt.Version == nil {
		version := 1
		reqInt.Version = &version
	}
	err := h.FileDataCtrl.InsertVideoPreview(ctx, &req)
	if err != nil {
		handler.Error(ctx, err)
		return
	}
	ctx.JSON(http.StatusOK, gin.H{})
}

func (h *FileHandler) GetFilesData(ctx *gin.Context) {
	var req fileData.GetFilesData
	if err := handler.BindJSON(ctx, &req); err != nil {
		ctx.JSON(http.StatusBadRequest, ente.NewBadRequestWithMessage(err.Error()))
		return
	}
	resp, err := h.FileDataCtrl.GetFilesData(ctx, req)
	if err != nil {
		handler.Error(ctx, err)
		return
	}
	ctx.JSON(http.StatusOK, resp)
}

// FileDataStatusDiff API won't really return status/diff for deleted files. The clients will primarily use this data to identify for which all files we already have preview generated or it's ML inference is done.
// This doesn't simulate perfect diff behaviour as we won't maintain a tombstone entries for the deleted API.
func (h *FileHandler) FileDataStatusDiff(ctx *gin.Context) {
	var req fileData.FDDiffRequest
	if err := handler.BindJSON(ctx, &req); err != nil {
		ctx.JSON(http.StatusBadRequest, ente.NewBadRequestWithMessage(err.Error()))
		return
	}
	if req.LastUpdatedAt == nil || *req.LastUpdatedAt < 0 {
		ctx.JSON(http.StatusBadRequest, ente.NewBadRequestWithMessage("lastUpdated is required and should be greater than or equal to 0"))
		return
	}
	diff, err := h.FileDataCtrl.FileDataStatusDiff(ctx, req)
	if err != nil {
		handler.Error(ctx, err)
		return
	}
	ctx.JSON(http.StatusOK, gin.H{
		"diff": diff,
	})
}

func (h *FileHandler) GetFileData(ctx *gin.Context) {
	var req fileData.GetFileData
	if err := ctx.ShouldBindQuery(&req); err != nil {
		ctx.JSON(http.StatusBadRequest, ente.NewBadRequestWithMessage(err.Error()))
		return
	}
	actorUser := auth.GetUserID(ctx.Request.Header)
	resp, err := h.FileDataCtrl.GetFileData(ctx, actorUser, req)
	if err != nil {
		handler.Error(ctx, err)
		return
	}
	if resp == nil {
		ctx.Status(http.StatusNoContent)
		return
	}
	ctx.JSON(http.StatusOK, gin.H{
		"data": resp,
	})
}

func (h *FileHandler) GetPreviewUploadURL(c *gin.Context) {
	var request fileData.PreviewUploadUrlRequest
	if err := c.ShouldBindQuery(&request); err != nil {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "Request binding failed %s", err))
		return
	}
	resp, err := h.FileDataCtrl.PreviewUploadURL(c, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *FileHandler) GetPreviewURL(c *gin.Context) {
	var request fileData.GetPreviewURLRequest
	if err := c.ShouldBindQuery(&request); err != nil {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "Request binding failed %s", err))
		return
	}
	actorUser := auth.GetUserID(c.Request.Header)
	url, err := h.FileDataCtrl.GetPreviewUrl(c, actorUser, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"url": url,
	})
}
