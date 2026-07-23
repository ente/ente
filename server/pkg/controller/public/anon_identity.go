package public

import (
	"fmt"
	"strings"

	"github.com/ente/museum/ente"
	socialentity "github.com/ente/museum/ente/social"
	socialrepo "github.com/ente/museum/pkg/repo/social"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	gonanoid "github.com/matoous/go-nanoid/v2"
)

// AnonIdentityController issues anonymous identities for public commenters.
type AnonIdentityController struct {
	JwtSecret     []byte
	AnonUsersRepo *socialrepo.AnonUsersRepository
}

// AnonIdentityResponse is returned when minting anon identities.
type AnonIdentityResponse struct {
	AnonUserID string `json:"anonUserID"`
	Token      string `json:"token"`
	ExpiresAt  int64  `json:"expiresAt"`
}

// CreateAnonIdentityRequest captures the profile payload for a new anonymous user.
type CreateAnonIdentityRequest struct {
	CollectionID int64
	Cipher       string
	Nonce        string
}

func (c *AnonIdentityController) Create(ctx *gin.Context, req CreateAnonIdentityRequest) (AnonIdentityResponse, error) {
	if err := ensureCommentsFeatureEnabled(ctx); err != nil {
		return AnonIdentityResponse{}, err
	}
	if strings.TrimSpace(req.Cipher) == "" || strings.TrimSpace(req.Nonce) == "" {
		return AnonIdentityResponse{}, ente.ErrBadRequest
	}
	if err := validateEncryptedPayloadLength(req.Cipher, maxAnonNameBytes, &ente.ErrAnonNameTooLong); err != nil {
		return AnonIdentityResponse{}, err
	}
	rawID, err := gonanoid.New()
	if err != nil {
		return AnonIdentityResponse{}, stacktrace.Propagate(err, "")
	}
	anonID := fmt.Sprintf("anon_%s", rawID)
	if err := c.AnonUsersRepo.Insert(ctx, socialentity.AnonUser{
		ID:           anonID,
		CollectionID: req.CollectionID,
		Cipher:       req.Cipher,
		Nonce:        req.Nonce,
	}); err != nil {
		return AnonIdentityResponse{}, stacktrace.Propagate(err, "")
	}
	token, expiresAt, err := ente.NewAnonymousIdentityToken(c.JwtSecret, anonID)
	if err != nil {
		return AnonIdentityResponse{}, stacktrace.Propagate(err, "")
	}
	return AnonIdentityResponse{
		AnonUserID: anonID,
		Token:      token,
		ExpiresAt:  expiresAt,
	}, nil
}
