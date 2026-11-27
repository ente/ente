package api

import (
	"net/http"

	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/email"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/gin-gonic/gin"
)

type EmailSubscriptionsHandler struct {
	Repo  *repo.EmailSubscriptionRepository
	Links *email.UnsubscribeLinks
}

func (h *EmailSubscriptionsHandler) Unsubscribe(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	c.Header("Referrer-Policy", "no-referrer")
	if h.Links == nil {
		c.Status(http.StatusNotFound)
		return
	}
	userID, emailType, valid := h.Links.Verify(c.Query("token"))
	if !valid {
		c.String(http.StatusBadRequest, "This unsubscribe link is invalid.")
		return
	}
	page := gin.H{"Category": emailType.Label()}
	if c.Request.Method == http.MethodGet {
		c.HTML(http.StatusOK, "email_unsubscribe.html", page)
		return
	}

	oneClick := c.PostForm("List-Unsubscribe") == "One-Click"
	if !oneClick && c.PostForm("confirm") != "1" {
		c.Status(http.StatusBadRequest)
		return
	}
	if err := h.Repo.Unsubscribe(c.Request.Context(), userID, emailType); err != nil {
		handler.Error(c, err)
		return
	}
	if oneClick {
		c.Status(http.StatusNoContent)
		return
	}
	page["Unsubscribed"] = true
	c.HTML(http.StatusOK, "email_unsubscribe.html", page)
}
