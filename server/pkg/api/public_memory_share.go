package api

import (
	"net/http"
	"strconv"

	"github.com/ente/museum/ente"
	fileData "github.com/ente/museum/ente/filedata"
	"github.com/ente/museum/pkg/controller/filedata"
	"github.com/ente/museum/pkg/controller/public"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

// PublicMemoryShareHandler exposes request handlers for publicly accessible memory shares
type PublicMemoryShareHandler struct {
	PublicCtrl   *public.MemoryShareController
	FileDataCtrl *filedata.Controller
}

// GetInfo returns the public memory share metadata
func (h *PublicMemoryShareHandler) GetInfo(c *gin.Context) {
	accessCtx := auth.MustGetMemoryShareAccessContext(c)

	share, err := h.PublicCtrl.GetPublicMemoryShare(c, accessCtx.AccessToken)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to get memory share"))
		return
	}

	c.JSON(http.StatusOK, ente.PublicMemoryShareResponse{
		MemoryShare: *share,
	})
}

// GetFiles returns the files in a public memory share
func (h *PublicMemoryShareHandler) GetFiles(c *gin.Context) {
	accessCtx := auth.MustGetMemoryShareAccessContext(c)

	resp, err := h.PublicCtrl.GetPublicFiles(c, accessCtx.ShareID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to get memory share files"))
		return
	}

	c.JSON(http.StatusOK, resp)
}

// GetThumbnail redirects to the file's thumbnail location
func (h *PublicMemoryShareHandler) GetThumbnail(c *gin.Context) {
	h.getFileForType(c, ente.THUMBNAIL)
}

// GetFile redirects to the file's full location
func (h *PublicMemoryShareHandler) GetFile(c *gin.Context) {
	h.getFileForType(c, ente.FILE)
}

// GetFileData returns HLS playlist data for video streaming
func (h *PublicMemoryShareHandler) GetFileData(c *gin.Context) {
	var req fileData.GetFileData
	if err := c.ShouldBindQuery(&req); err != nil {
		handler.Error(c, ente.NewBadRequestWithMessage(err.Error()))
		return
	}
	if req.Type != ente.PreviewVideo {
		handler.Error(c, ente.NewBadRequestWithMessage("unsupported object type"))
		return
	}

	accessCtx := auth.MustGetMemoryShareAccessContext(c)
	ownerID, err := h.PublicCtrl.GetAccessibleFileOwnerID(c, accessCtx.ShareID, req.FileID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to validate file access"))
		return
	}

	resp, err := h.FileDataCtrl.GetFileData(c, ownerID, req)
	if err != nil {
		handler.Error(c, err)
		return
	}
	if resp == nil {
		c.Status(http.StatusNoContent)
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": resp})
}

// GetPreviewURL returns pre-signed URL for video preview data
func (h *PublicMemoryShareHandler) GetPreviewURL(c *gin.Context) {
	var req fileData.GetPreviewURLRequest
	if err := c.ShouldBindQuery(&req); err != nil {
		handler.Error(c, ente.NewBadRequestWithMessage(err.Error()))
		return
	}

	accessCtx := auth.MustGetMemoryShareAccessContext(c)
	ownerID, err := h.PublicCtrl.GetAccessibleFileOwnerID(c, accessCtx.ShareID, req.FileID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to validate file access"))
		return
	}

	url, err := h.FileDataCtrl.GetPreviewUrl(c, ownerID, req)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to get preview URL"))
		return
	}
	c.JSON(http.StatusOK, gin.H{"url": url})
}

func (h *PublicMemoryShareHandler) getFileForType(c *gin.Context, objType ente.ObjectType) {
	fileID, err := strconv.ParseInt(c.Param("fileID"), 10, 64)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "invalid file ID"))
		return
	}

	accessCtx := auth.MustGetMemoryShareAccessContext(c)

	url, err := h.PublicCtrl.GetPublicFileURL(c, accessCtx.ShareID, fileID, objType)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to get file URL"))
		return
	}

	c.Redirect(http.StatusTemporaryRedirect, url)
}
