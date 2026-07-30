package api

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/space/controller"
	"github.com/ente/museum/space/models"
	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
)

func (h *Handlers) RequireSpaceBrowserSession() gin.HandlerFunc {
	return func(c *gin.Context) {
		sessionToken := strings.TrimSpace(c.GetHeader(controller.SpaceBrowserSessionTokenHeader))
		if sessionToken == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing session"})
			return
		}
		session, err := h.Module.Sessions.ValidateBrowserSession(c, sessionToken)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid session"})
			return
		}
		c.Request.Header.Set("X-Auth-User-ID", strconv.FormatInt(session.UserID, 10))
		c.Next()
	}
}

func (h *Handlers) RequireSelectedSpace() gin.HandlerFunc {
	return func(c *gin.Context) {
		if err := h.Module.RequireSelectedSpace(c, c.Param("spaceID")); err != nil {
			respondJSON(c, nil, err)
			c.Abort()
			return
		}
		c.Next()
	}
}

func (h *Handlers) CreateBrowserSession(c *gin.Context) {
	if app, ok := auth.GetAuthenticatedApp(c); !ok || app != ente.Photos {
		respondJSON(c, nil, ente.ErrPermissionDenied)
		return
	}
	var req models.SpaceBrowserSessionRequest
	if !bindJSON(c, &req) {
		return
	}
	userID := auth.GetUserID(c.Request.Header)
	if userID <= 0 {
		respondJSON(c, nil, ente.ErrAuthenticationRequired)
		return
	}
	token := strings.TrimSpace(auth.GetToken(c))
	created, err := h.Module.Sessions.CreateBrowserSession(c, userID, token, req.SessionWrapKey)
	if err != nil {
		respondJSON(c, nil, err)
		return
	}
	if h.Module.UserTokens != nil {
		if err := h.Module.UserTokens.TerminateSession(userID, token); err != nil {
			log.WithError(err).WithField("user_id", userID).Warn("Failed to evict exchanged Space bootstrap token")
		}
	}
	respondJSON(c, created.Response, nil)
}

func (h *Handlers) BootstrapBrowserSession(c *gin.Context) {
	sessionToken := strings.TrimSpace(c.GetHeader(controller.SpaceBrowserSessionTokenHeader))
	resp, err := h.Module.Sessions.BootstrapBrowserSession(c, sessionToken)
	respondJSON(c, resp, err)
}

func (h *Handlers) DeleteBrowserSession(c *gin.Context) {
	sessionToken := strings.TrimSpace(c.GetHeader(controller.SpaceBrowserSessionTokenHeader))
	err := h.Module.Sessions.RevokeBrowserSessions(c, sessionToken)
	respondStatus(c, err)
}
