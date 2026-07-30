package controller

import (
	"bytes"
	"crypto/ecdh"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"errors"
	"net/http"
	"net/mail"
	"net/url"
	"strings"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/space/models"
	"github.com/ente/museum/space/repo"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

const (
	spaceWebPushEndpointMaxBytes = 2048
	spaceWebPushP256dhMaxBytes   = 256
	spaceWebPushAuthMaxBytes     = 128
)

type WebPushController struct {
	webPushRepo *repo.WebPushRepository
	links       *LinksController
	config      *SpaceWebPushConfig
}

type SpaceWebPushConfig struct {
	publicKey  string
	privateKey string
	subscriber string
}

func (c *WebPushController) VAPIDPublicKey() (*models.SpaceWebPushVAPIDKeyResponse, error) {
	if c.config == nil {
		return nil, &ente.ApiError{
			Code:           ente.ErrorCode("SPACE_WEB_PUSH_UNAVAILABLE"),
			Message:        "space web push is unavailable",
			HttpStatusCode: http.StatusServiceUnavailable,
		}
	}
	return &models.SpaceWebPushVAPIDKeyResponse{PublicKey: c.config.publicKey}, nil
}

func (c *WebPushController) UpsertAccountSubscription(
	ctx *gin.Context,
	sessionToken string,
	req models.SpaceWebPushSubscriptionRequest,
) (*models.SpaceWebPushTargetResponse, error) {
	endpoint, p256dh, auth, err := validatedWebPushSubscription(req)
	if err != nil {
		return nil, err
	}
	sessionHash := sha256.Sum256([]byte(sessionToken))
	targetID, err := c.webPushRepo.UpsertAccountSubscription(
		ctx,
		sessionHash[:],
		endpoint,
		p256dh,
		auth,
	)
	if err != nil {
		return nil, err
	}
	return &models.SpaceWebPushTargetResponse{TargetID: targetID}, nil
}

func (c *WebPushController) DeleteAccountSubscription(
	ctx *gin.Context,
	sessionToken string,
	req models.SpaceWebPushUnsubscriptionRequest,
) error {
	endpoint := strings.TrimSpace(req.Endpoint)
	if err := validateWebPushEndpoint(endpoint); err != nil {
		return err
	}
	sessionHash := sha256.Sum256([]byte(sessionToken))
	return c.webPushRepo.DeleteAccountSubscription(ctx, sessionHash[:], endpoint)
}

func (c *WebPushController) UpsertLinkSubscription(
	ctx *gin.Context,
	slug string,
	req models.SpaceWebPushSubscriptionRequest,
) (*models.SpaceWebPushTargetResponse, error) {
	endpoint, p256dh, auth, err := validatedWebPushSubscription(req)
	if err != nil {
		return nil, err
	}
	link, err := c.links.Authorize(ctx, slug)
	if err != nil {
		return nil, err
	}
	targetID, err := c.webPushRepo.UpsertLinkSubscription(
		ctx,
		link.LinkID,
		endpoint,
		p256dh,
		auth,
	)
	if err != nil {
		if errors.Is(err, repo.ErrSpaceWebPushLinkSubscriptionLimit) {
			return nil, &ente.ApiError{
				Code:           ente.ErrorCode("SPACE_WEB_PUSH_SUBSCRIPTION_LIMIT"),
				Message:        "too many web push subscriptions for this Space link",
				HttpStatusCode: http.StatusTooManyRequests,
			}
		}
		if errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
			return nil, ente.ErrNotFound
		}
		return nil, err
	}
	return &models.SpaceWebPushTargetResponse{TargetID: targetID}, nil
}

func (c *WebPushController) DeleteLinkSubscription(
	ctx *gin.Context,
	slug string,
	req models.SpaceWebPushUnsubscriptionRequest,
) error {
	endpoint := strings.TrimSpace(req.Endpoint)
	if err := validateWebPushEndpoint(endpoint); err != nil {
		return err
	}
	link, err := c.links.Authorize(ctx, slug)
	if err != nil {
		return err
	}
	return c.webPushRepo.DeleteLinkSubscription(ctx, link.LinkID, endpoint)
}

func validatedWebPushSubscription(
	req models.SpaceWebPushSubscriptionRequest,
) (string, string, string, error) {
	endpoint := strings.TrimSpace(req.Endpoint)
	p256dh := strings.TrimSpace(req.Keys.P256dh)
	auth := strings.TrimSpace(req.Keys.Auth)
	if err := validateWebPushSubscription(endpoint, p256dh, auth); err != nil {
		return "", "", "", err
	}
	return endpoint, p256dh, auth, nil
}

func validateWebPushSubscription(endpoint, p256dh, auth string) error {
	if err := validateWebPushEndpoint(endpoint); err != nil {
		return err
	}
	if p256dh == "" || len(p256dh) > spaceWebPushP256dhMaxBytes {
		return ente.NewBadRequestWithMessage("invalid web push p256dh key")
	}
	decodedP256dh, err := base64.RawURLEncoding.DecodeString(strings.TrimRight(p256dh, "="))
	_, publicKeyErr := ecdh.P256().NewPublicKey(decodedP256dh)
	if err != nil || len(decodedP256dh) != 65 || publicKeyErr != nil {
		return ente.NewBadRequestWithMessage("invalid web push p256dh key")
	}
	if auth == "" || len(auth) > spaceWebPushAuthMaxBytes {
		return ente.NewBadRequestWithMessage("invalid web push auth key")
	}
	decodedAuth, err := base64.RawURLEncoding.DecodeString(strings.TrimRight(auth, "="))
	if err != nil || len(decodedAuth) != 16 {
		return ente.NewBadRequestWithMessage("invalid web push auth key")
	}
	return nil
}

func NewSpaceWebPushConfig(publicKey, privateKey, subscriber string) *SpaceWebPushConfig {
	config := &SpaceWebPushConfig{
		publicKey:  strings.TrimSpace(publicKey),
		privateKey: strings.TrimSpace(privateKey),
		subscriber: strings.TrimSpace(subscriber),
	}
	decodedPublicKey, publicKeyErr := decodeBase64URL(config.publicKey)
	_, publicCurveErr := ecdh.P256().NewPublicKey(decodedPublicKey)
	decodedPrivateKey, privateKeyErr := decodeBase64URL(config.privateKey)
	parsedPrivateKey, privateCurveErr := ecdh.P256().NewPrivateKey(decodedPrivateKey)
	parsedSubscriber, subscriberErr := mail.ParseAddress(config.subscriber)
	if publicKeyErr != nil ||
		len(decodedPublicKey) != 65 ||
		publicCurveErr != nil ||
		privateKeyErr != nil ||
		len(decodedPrivateKey) != 32 ||
		privateCurveErr != nil ||
		!bytes.Equal(parsedPrivateKey.PublicKey().Bytes(), decodedPublicKey) ||
		subscriberErr != nil ||
		parsedSubscriber.Address != config.subscriber {
		return nil
	}
	return config
}

func decodeBase64URL(value string) ([]byte, error) {
	return base64.RawURLEncoding.DecodeString(strings.TrimRight(value, "="))
}

func validateWebPushEndpoint(endpoint string) error {
	if endpoint == "" ||
		len(endpoint) > spaceWebPushEndpointMaxBytes ||
		strings.Contains(endpoint, "#") {
		return ente.NewBadRequestWithMessage("invalid web push endpoint")
	}
	parsed, err := url.ParseRequestURI(endpoint)
	if err != nil ||
		parsed.Scheme != "https" ||
		parsed.Hostname() == "" ||
		parsed.User != nil ||
		parsed.Fragment != "" {
		return ente.NewBadRequestWithMessage("invalid web push endpoint")
	}
	return nil
}
