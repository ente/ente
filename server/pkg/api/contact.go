package api

import (
	"net/http"

	"github.com/ente/museum/ente"
	contactmodel "github.com/ente/museum/ente/contact"
	contactcontroller "github.com/ente/museum/pkg/controller/contact"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

type ContactHandler struct {
	Controller *contactcontroller.Controller
}

func (h *ContactHandler) Create(c *gin.Context) {
	var request contactmodel.CreateRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "request binding failed"))
		return
	}
	resp, err := h.Controller.Create(c, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to create contact"))
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *ContactHandler) Get(c *gin.Context) {
	resp, err := h.Controller.Get(c, c.Param("id"))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to fetch contact"))
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *ContactHandler) GetDiff(c *gin.Context) {
	var request contactmodel.DiffRequest
	if err := c.ShouldBindQuery(&request); err != nil {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "request binding failed %s", err))
		return
	}
	diff, err := h.Controller.GetDiff(c, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to fetch contact diff"))
		return
	}
	c.JSON(http.StatusOK, gin.H{"diff": diff})
}

func (h *ContactHandler) Update(c *gin.Context) {
	var request contactmodel.UpdateRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "request binding failed"))
		return
	}
	resp, err := h.Controller.Update(c, c.Param("id"), request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to update contact"))
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *ContactHandler) Delete(c *gin.Context) {
	if err := h.Controller.Delete(c, c.Param("id")); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to delete contact"))
		return
	}
	c.Status(http.StatusOK)
}

func (h *ContactHandler) GetAttachmentUploadURL(c *gin.Context) {
	var request contactmodel.AttachmentUploadURLRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "request binding failed"))
		return
	}
	resp, err := h.Controller.GetAttachmentUploadURL(c, c.Param("type"), request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to create attachment upload url"))
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *ContactHandler) GetProfilePictureUploadURL(c *gin.Context) {
	c.Params = append(c.Params, gin.Param{Key: "type", Value: string(contactmodel.ProfilePicture)})
	h.GetAttachmentUploadURL(c)
}

func (h *ContactHandler) AttachContactAttachment(c *gin.Context) {
	var request contactmodel.CommitAttachmentRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "request binding failed"))
		return
	}
	resp, err := h.Controller.AttachContactAttachment(c, c.Param("id"), c.Param("type"), request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to attach contact attachment"))
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *ContactHandler) AttachProfilePicture(c *gin.Context) {
	c.Params = append(c.Params, gin.Param{Key: "type", Value: string(contactmodel.ProfilePicture)})
	h.AttachContactAttachment(c)
}

func (h *ContactHandler) GetAttachment(c *gin.Context) {
	resp, err := h.Controller.GetAttachmentURL(c, c.Param("type"), c.Param("attachmentID"))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to get attachment url"))
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *ContactHandler) GetProfilePicture(c *gin.Context) {
	attachmentID := c.Query("attachmentID")
	if attachmentID != "" {
		c.Params = append(c.Params, gin.Param{Key: "type", Value: string(contactmodel.ProfilePicture)})
		c.Params = append(c.Params, gin.Param{Key: "attachmentID", Value: attachmentID})
		h.GetAttachment(c)
		return
	}
	resp, err := h.Controller.GetCurrentContactAttachmentURL(c, c.Param("id"), string(contactmodel.ProfilePicture))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to get profile picture url"))
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *ContactHandler) DeleteContactAttachment(c *gin.Context) {
	resp, err := h.Controller.DeleteContactAttachment(c, c.Param("id"), c.Param("type"))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to delete contact attachment"))
		return
	}
	c.JSON(http.StatusOK, resp)
}

func (h *ContactHandler) DeleteProfilePicture(c *gin.Context) {
	c.Params = append(c.Params, gin.Param{Key: "type", Value: string(contactmodel.ProfilePicture)})
	h.DeleteContactAttachment(c)
}

func (h *ContactHandler) GetCurrentContactAttachment(c *gin.Context) {
	resp, err := h.Controller.GetCurrentContactAttachmentURL(c, c.Param("id"), c.Param("type"))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to get current contact attachment url"))
		return
	}
	c.JSON(http.StatusOK, resp)
}
