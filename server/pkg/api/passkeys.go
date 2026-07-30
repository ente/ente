package api

import (
	"net/http"

	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type PasskeyHandler struct {
	Controller *controller.PasskeyController
}

func (h *PasskeyHandler) GetPasskeys(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)

	passkeys, accountsURL, err := h.Controller.GetPasskeysAndAccountsURL(userID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"accountsUrl": accountsURL,
		"passkeys":    passkeys,
	})
}

func (h *PasskeyHandler) RenamePasskey(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)

	passkeyID := uuid.MustParse(c.Param("passkeyID"))
	newName := c.Query("friendlyName")

	err := h.Controller.RenamePasskey(userID, passkeyID, newName)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}

	c.JSON(http.StatusOK, gin.H{})
}

func (h *PasskeyHandler) DeletePasskey(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)

	passkeyID := uuid.MustParse(c.Param("passkeyID"))

	err := h.Controller.DeletePasskey(userID, passkeyID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}

	c.JSON(http.StatusOK, gin.H{})
}

func (h *PasskeyHandler) BeginRegistration(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)

	options, _, sessionID, err := h.Controller.BeginRegistration(userID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"options":   options,
		"sessionID": sessionID,
	})
}

func (h *PasskeyHandler) FinishRegistration(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)

	friendlyName := c.Query("friendlyName")
	sessionID := uuid.MustParse(c.Query("sessionID"))

	err := h.Controller.FinishRegistration(userID, friendlyName, c.Request, sessionID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}

	c.JSON(http.StatusOK, gin.H{})
}
