package controller

import (
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"errors"
	"strings"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/auth"
	timeutil "github.com/ente/museum/pkg/utils/time"
	"github.com/ente/museum/space/models"
	"github.com/ente/museum/space/repo"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

const (
	spaceBrowserSessionDurationDays = 365
	spaceBrowserSessionTouchMinutes = 1
	spaceBrowserSessionWrapKeyBytes = 32
)
const SpaceBrowserSessionTokenHeader = "X-Space-Session-Token"

type SessionsController struct {
	SessionsRepo *repo.SessionsRepository
}

type CreatedBrowserSession struct {
	Response models.SpaceBrowserSessionResponse
}

func (c *SessionsController) CreateBrowserSession(ctx *gin.Context, userID int64, authToken string, sessionWrapKey string) (*CreatedBrowserSession, error) {
	sessionWrapKey = strings.TrimSpace(sessionWrapKey)
	if len(sessionWrapKey) != base64.StdEncoding.EncodedLen(spaceBrowserSessionWrapKeyBytes) {
		return nil, ente.NewBadRequestWithMessage("sessionWrapKey must be a base64-encoded 32-byte key")
	}
	decodedWrapKey, err := base64.StdEncoding.DecodeString(sessionWrapKey)
	if err != nil || len(decodedWrapKey) != spaceBrowserSessionWrapKeyBytes {
		return nil, ente.NewBadRequestWithMessage("sessionWrapKey must be a base64-encoded 32-byte key")
	}
	sessionToken := auth.GenerateURLSafeRandomString(32)
	sessionHash := sha256.Sum256([]byte(sessionToken))
	expiresAt := timeutil.NDaysFromNow(spaceBrowserSessionDurationDays)
	if err := c.SessionsRepo.ExchangeBrowserSession(ctx, authToken, sessionHash[:], userID, sessionWrapKey, expiresAt); err != nil {
		return nil, err
	}
	return &CreatedBrowserSession{
		Response: models.SpaceBrowserSessionResponse{SessionToken: sessionToken},
	}, nil
}

func (c *SessionsController) BootstrapBrowserSession(ctx *gin.Context, sessionToken string) (*models.SpaceBrowserSessionBootstrapResponse, error) {
	session, err := c.ValidateBrowserSession(ctx, sessionToken)
	if err != nil {
		return nil, err
	}
	return &models.SpaceBrowserSessionBootstrapResponse{
		SessionWrapKey: session.SessionWrapKey,
	}, nil
}

func (c *SessionsController) ValidateBrowserSession(ctx *gin.Context, sessionToken string) (*repo.SpaceBrowserSessionRecord, error) {
	return validateBrowserSession(ctx, c.SessionsRepo, sessionToken)
}

func validateBrowserSession(ctx *gin.Context, sessionsRepo *repo.SessionsRepository, sessionToken string) (*repo.SpaceBrowserSessionRecord, error) {
	if sessionToken == "" || sessionsRepo == nil {
		return nil, ente.ErrAuthenticationRequired
	}
	sessionHash := sha256.Sum256([]byte(sessionToken))
	session, err := sessionsRepo.GetBrowserSession(ctx, sessionHash[:])
	if err != nil {
		if errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
			return nil, ente.ErrAuthenticationRequired
		}
		return nil, err
	}
	now := timeutil.Microseconds()
	if session.ExpiresAt <= now {
		_ = sessionsRepo.DeleteBrowserSession(ctx, sessionHash[:])
		return nil, ente.ErrAuthenticationRequired
	}
	touchBefore := now - spaceBrowserSessionTouchMinutes*timeutil.MicroSecondsInOneMinute
	if session.LastUsedAt <= touchBefore {
		if err := sessionsRepo.TouchBrowserSession(ctx, sessionHash[:], touchBefore); err != nil {
			return nil, err
		}
	}
	return session, nil
}

func (c *SessionsController) RevokeBrowserSessions(ctx *gin.Context, sessionToken string) error {
	sessionHash := sha256.Sum256([]byte(sessionToken))
	return c.SessionsRepo.DeleteBrowserSessionsForToken(ctx, sessionHash[:])
}
