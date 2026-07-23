package api

import (
	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"net/http"
	"strconv"
)

// ShareUrl a sharable url for the file
func (h *FileHandler) ShareUrl(c *gin.Context) {
	var file ente.CreateFileUrl
	if err := handler.BindJSON(c, &file); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}

	response, err := h.FileUrlCtrl.CreateLink(c, file)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, response)
}

func (h *FileHandler) LinkInfo(c *gin.Context) {
	fileResp, linkMeta, err := h.FileUrlCtrl.Info(c)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	response := gin.H{
		"file": fileResp,
	}
	if linkMeta != nil {
		response["link"] = linkMeta
	}
	if linkDeviceToken, ok := c.Get(auth.LinkDeviceTokenResponseKey); ok {
		if token, ok := linkDeviceToken.(string); ok && token != "" {
			c.Header(auth.LinkDeviceTokenResponseHeader, token)
		}
	}
	c.JSON(http.StatusOK, response)
}

func (h *FileHandler) PasswordInfo(c *gin.Context) {
	resp, err := h.FileUrlCtrl.PassInfo(c)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"nonce":    resp.Nonce,
		"opsLimit": resp.OpsLimit,
		"memLimit": resp.MemLimit,
	})
}

func (h *FileHandler) LinkThumbnail(c *gin.Context) {
	linkCtx := auth.MustGetFileLinkAccessContext(c)
	url, err := h.Controller.GetThumbnailURLForOwner(c, linkCtx.OwnerID, linkCtx.FileID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Redirect(http.StatusTemporaryRedirect, url)
}

func (h *FileHandler) LinkFile(c *gin.Context) {
	linkCtx := auth.MustGetFileLinkAccessContext(c)
	url, err := h.Controller.GetFileURLForOwner(c, linkCtx.OwnerID, linkCtx.FileID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Redirect(http.StatusTemporaryRedirect, url)
}

func (h *FileHandler) DisableUrl(c *gin.Context) {
	cID, err := strconv.ParseInt(c.Param("fileID"), 10, 64)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, ""))
		return
	}
	err = h.FileUrlCtrl.Disable(c, cID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

func (h *FileHandler) GetUrls(c *gin.Context) {
	sinceTime, err := strconv.ParseInt(c.Query("sinceTime"), 10, 64)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "sinceTime parsing failed"))
		return
	}
	limit := 500
	if c.Query("limit") != "" {
		limit, err = strconv.Atoi(c.Query("limit"))
		if err != nil || limit < 1 {
			handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, ""))
			return
		}
	}
	response, err := h.FileUrlCtrl.GetUrls(c, sinceTime, int64(limit))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"diff": response,
	})
}

// VerifyPassword verifies the password for given link access token and return signed jwt token if it's valid
func (h *FileHandler) VerifyPassword(c *gin.Context) {
	var req ente.VerifyPasswordRequest
	if err := handler.BindJSON(c, &req); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	resp, err := h.FileUrlCtrl.VerifyPassword(c, req)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, resp)
}

// UpdateFileURL updates the share URL for a file
func (h *FileHandler) UpdateFileURL(c *gin.Context) {
	var req ente.UpdateFileUrl
	if err := handler.BindJSON(c, &req); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	response, err := h.FileUrlCtrl.UpdateSharedUrl(c, req)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"result": response,
	})
}
