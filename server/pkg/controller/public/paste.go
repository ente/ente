package public

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/ente/museum/ente"
	entebase "github.com/ente/museum/ente/base"
	enteJWT "github.com/ente/museum/ente/jwt"
	"github.com/ente/museum/pkg/repo/public"
	timeUtil "github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v4"
	"github.com/lithammer/shortuuid/v3"
)

const (
	pasteAccessTokenLength = 10
	// For 4k input, worst case is 32040 bytes after JSON escaping (up to 6x),
	// secretstream overhead (+17), and base64 encoding. Keep a small margin.
	maxCiphertextBytes = 32256
	pasteTTL           = 24 * time.Hour
	guardTTL           = 2 * time.Minute
	guardCookieName    = "paste_guard"
)

type PasteController struct {
	PasteRepo   *public.PasteRepository
	JwtSecret   []byte
	PasteOrigin string
}

func (c *PasteController) Create(
	ctx *gin.Context,
	req *ente.CreatePasteRequest,
) (*ente.CreatePasteResponse, error) {
	if err := req.Validate(maxCiphertextBytes); err != nil {
		return nil, stacktrace.Propagate(err, "invalid paste request")
	}

	expiresAt := timeUtil.Microseconds() + pasteTTL.Microseconds()
	for range 5 {
		accessToken := strings.ToUpper(shortuuid.New()[0:pasteAccessTokenLength])
		idPtr, err := entebase.NewID("ppt")
		if err != nil {
			return nil, stacktrace.Propagate(err, "failed to generate paste id")
		}
		err = c.PasteRepo.Insert(ctx, *idPtr, accessToken, req, expiresAt)
		if err == nil {
			return &ente.CreatePasteResponse{
				AccessToken: accessToken,
				ExpiresAt:   expiresAt,
			}, nil
		}
		if err == ente.ErrAccessTokenInUse {
			continue
		}
		return nil, stacktrace.Propagate(err, "failed to create paste token")
	}

	return nil, stacktrace.Propagate(ente.ErrAccessTokenInUse, "failed to generate unique paste token")
}

func (c *PasteController) SetGuard(
	ctx *gin.Context,
	req *ente.PasteTokenRequest,
) error {
	if err := req.Validate(); err != nil {
		return stacktrace.Propagate(err, "invalid paste token request")
	}
	accessToken := strings.TrimSpace(req.AccessToken)

	if isLikelyPreviewRequest(ctx) {
		return stacktrace.Propagate(newPasteUnavailableError(), "preview request blocked")
	}

	exists, err := c.PasteRepo.ExistsActiveByToken(ctx, accessToken)
	if err != nil {
		return stacktrace.Propagate(err, "failed to check paste token")
	}
	if !exists {
		return stacktrace.Propagate(newPasteUnavailableError(), "paste unavailable")
	}

	claim := &enteJWT.PasteGuardClaim{
		AccessToken:   accessToken,
		UserAgentHash: hashUserAgent(ctx.GetHeader("User-Agent")),
		ExpiryTime:    timeUtil.Microseconds() + guardTTL.Microseconds(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claim)
	tokenString, err := token.SignedString(c.JwtSecret)
	if err != nil {
		return stacktrace.Propagate(err, "failed to sign paste guard token")
	}

	secureCookie := shouldSetSecureCookie(ctx)
	ctx.SetSameSite(http.SameSiteStrictMode)
	ctx.SetCookie(guardCookieName, tokenString, int(guardTTL.Seconds()), "/", "", secureCookie, true)
	return nil
}

func (c *PasteController) Consume(
	ctx *gin.Context,
	req *ente.PasteTokenRequest,
) (*ente.PastePayload, error) {
	if err := req.Validate(); err != nil {
		return nil, stacktrace.Propagate(err, "invalid paste token request")
	}
	accessToken := strings.TrimSpace(req.AccessToken)

	if ctx.GetHeader("X-Paste-Consume") != "1" {
		return nil, stacktrace.Propagate(ente.NewBadRequestWithMessage("missing consume confirmation"), "invalid consume header")
	}
	if isLikelyPreviewRequest(ctx) {
		return nil, stacktrace.Propagate(newPasteUnavailableError(), "preview request blocked")
	}
	if err := c.validateOrigin(ctx); err != nil {
		return nil, stacktrace.Propagate(err, "invalid origin")
	}
	if err := c.validateGuard(ctx, accessToken); err != nil {
		return nil, stacktrace.Propagate(err, "invalid guard")
	}

	payload, err := c.PasteRepo.ConsumeByToken(ctx, accessToken)
	if err != nil {
		if err == ente.ErrNotFound {
			return nil, stacktrace.Propagate(newPasteUnavailableError(), "paste unavailable")
		}
		return nil, stacktrace.Propagate(err, "failed to consume paste")
	}

	ctx.SetSameSite(http.SameSiteStrictMode)
	ctx.SetCookie(guardCookieName, "", -1, "/", "", shouldSetSecureCookie(ctx), true)
	return payload, nil
}

func (c *PasteController) validateOrigin(ctx *gin.Context) error {
	if c.PasteOrigin == "" {
		return nil
	}

	origin := strings.TrimSpace(ctx.GetHeader("Origin"))
	// Some clients might omit Origin; rely on guard cookie in that case.
	if origin == "" {
		return nil
	}
	if origin != c.PasteOrigin {
		return newPasteUnavailableError()
	}
	return nil
}

func (c *PasteController) validateGuard(ctx *gin.Context, accessToken string) error {
	guardToken, err := ctx.Cookie(guardCookieName)
	if err != nil || guardToken == "" {
		return newPasteUnavailableError()
	}

	parsedToken, err := jwt.ParseWithClaims(guardToken, &enteJWT.PasteGuardClaim{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return c.JwtSecret, nil
	})
	if err != nil {
		return newPasteUnavailableError()
	}
	claim, ok := parsedToken.Claims.(*enteJWT.PasteGuardClaim)
	if !ok || !parsedToken.Valid {
		return newPasteUnavailableError()
	}
	if claim.AccessToken != accessToken {
		return newPasteUnavailableError()
	}
	if claim.UserAgentHash != hashUserAgent(ctx.GetHeader("User-Agent")) {
		return newPasteUnavailableError()
	}
	return nil
}

func hashUserAgent(userAgent string) string {
	sum := sha256.Sum256([]byte(strings.TrimSpace(userAgent)))
	return hex.EncodeToString(sum[:])
}

func shouldSetSecureCookie(ctx *gin.Context) bool {
	if ctx.Request.TLS != nil {
		return true
	}
	origin := strings.TrimSpace(ctx.GetHeader("Origin"))
	return strings.HasPrefix(origin, "https://")
}

func isLikelyPreviewRequest(ctx *gin.Context) bool {
	ua := strings.ToLower(strings.TrimSpace(ctx.GetHeader("User-Agent")))
	purpose := strings.ToLower(strings.TrimSpace(ctx.GetHeader("Purpose")))
	secPurpose := strings.ToLower(strings.TrimSpace(ctx.GetHeader("Sec-Purpose")))

	if strings.Contains(purpose, "prefetch") || strings.Contains(purpose, "preview") ||
		strings.Contains(secPurpose, "prefetch") || strings.Contains(secPurpose, "preview") ||
		strings.Contains(secPurpose, "prerender") {
		return true
	}

	previewUATokens := []string{
		"bot", "crawler", "spider", "preview", "slackbot", "discordbot",
		"twitterbot", "facebookexternalhit", "whatsappbot", "telegrambot",
		"linkedinbot", "skypeuripreview", "googlebot",
	}
	for _, token := range previewUATokens {
		if strings.Contains(ua, token) {
			return true
		}
	}
	return false
}

func newPasteUnavailableError() *ente.ApiError {
	return &ente.ApiError{
		Code:           ente.NotFoundError,
		Message:        "Paste is unavailable",
		HttpStatusCode: http.StatusGone,
	}
}
