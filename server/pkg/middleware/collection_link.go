package middleware

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"strings"

	"golang.org/x/net/idna"

	"github.com/ente/museum/pkg/repo/remotestore"
	"github.com/gin-contrib/requestid"
	"github.com/spf13/viper"

	public2 "github.com/ente/museum/pkg/controller/public"
	"github.com/ente/museum/pkg/repo/public"
	socialrepo "github.com/ente/museum/pkg/repo/social"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/controller/discord"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/network"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/patrickmn/go-cache"
	"github.com/sirupsen/logrus"
)

var passwordWhiteListedURLs = []string{"/public-collection/info", "/public-collection/verify-password"}

// CollectionLinkMiddleware intercepts and authenticates incoming requests
type CollectionLinkMiddleware struct {
	CollectionLinkRepo   *public.CollectionLinkRepo
	PublicCollectionCtrl *public2.CollectionLinkController
	CollectionRepo       *repo.CollectionRepository
	AnonUsersRepo        *socialrepo.AnonUsersRepository
	Cache                *cache.Cache
	BillingCtrl          *controller.BillingController
	DiscordController    *discord.DiscordController
	RemoteStoreRepo      *remotestore.Repository
	AnonIdentitySecret   []byte
}

// Authenticate returns a middle ware that extracts the `X-Auth-Access-Token`
// within the header of a request and uses it to validate the access token and set the
// ente.PublicAccessContext with auth.PublicAccessKey as key
func (m *CollectionLinkMiddleware) Authenticate(urlSanitizer func(_ *gin.Context) string) gin.HandlerFunc {
	return func(c *gin.Context) {
		accessToken := auth.GetAccessToken(c)
		if accessToken == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing accessToken", "context": "album_link"})
			return
		}
		clientIP := network.GetClientIP(c)
		userAgent := c.GetHeader("User-Agent")
		var publicCollectionSummary ente.PublicCollectionSummary
		var err error
		reqPath := urlSanitizer(c)
		shouldCheckDeviceLimit := shouldCheckCollectionLinkDeviceLimit(reqPath)
		passwordValidated := false

		cacheKey := computeHashKeyForList([]string{accessToken, clientIP, userAgent, c.GetHeader("Origin")}, ":")
		var cachedValue interface{}
		cacheHit := false
		if !shouldCheckDeviceLimit {
			cachedValue, cacheHit = m.Cache.Get(cacheKey)
		}
		if !cacheHit {
			publicCollectionSummary, err = m.CollectionLinkRepo.GetCollectionSummaryByToken(c, accessToken)
			if err != nil {
				c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
				return
			}
			if publicCollectionSummary.IsDisabled {
				c.AbortWithStatusJSON(http.StatusGone, gin.H{"error": "disabled token"})
				return
			}
			// validate if user still has active paid subscription
			isFreeUser, err := m.validateOwnersSubscription(c, publicCollectionSummary.CollectionID)
			if err != nil {
				logrus.WithError(err).Warn("failed to verify active paid subscription")
				c.AbortWithStatusJSON(http.StatusGone, gin.H{"error": "no active subscription"})
				return
			}
			// Override device limit to 5 for free users
			if isFreeUser {
				publicCollectionSummary.DeviceLimit = public2.FreeUserDeviceLimit
			}

			if publicCollectionSummary.ValidTill > 0 && // expiry time is defined, 0 indicates no expiry
				publicCollectionSummary.ValidTill < time.Microseconds() {
				c.AbortWithStatusJSON(http.StatusGone, gin.H{"error": "expired token"})
				return
			}
			if publicCollectionSummary.PassHash != nil && *publicCollectionSummary.PassHash != "" {
				if err = m.validatePassword(c, reqPath, publicCollectionSummary); err != nil {
					logrus.WithError(err).Warn("password validation failed")
					c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": err})
					return
				}
				passwordValidated = true
			}

			if shouldCheckDeviceLimit {
				linkDeviceToken, reached, limitErr := m.checkDeviceLimit(c, accessToken, publicCollectionSummary, clientIP, userAgent)
				if limitErr != nil {
					logrus.WithError(limitErr).Error("failed to check device limit")
					c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"error": "something went wrong"})
					return
				}
				if reached {
					c.AbortWithStatusJSON(
						ente.ErrLinkDeviceLimitExceeded.HttpStatusCode,
						&ente.ErrLinkDeviceLimitExceeded,
					)
					return
				}
				if linkDeviceToken != "" {
					c.Set(auth.LinkDeviceTokenResponseKey, linkDeviceToken)
				}
			}
		} else {
			publicCollectionSummary = cachedValue.(ente.PublicCollectionSummary)
		}

		if publicCollectionSummary.ValidTill > 0 && // expiry time is defined, 0 indicates no expiry
			publicCollectionSummary.ValidTill < time.Microseconds() {
			c.AbortWithStatusJSON(http.StatusGone, gin.H{"error": "expired token"})
			return
		}

		// checks password protected public collection
		if !passwordValidated && publicCollectionSummary.PassHash != nil && *publicCollectionSummary.PassHash != "" {
			if err = m.validatePassword(c, reqPath, publicCollectionSummary); err != nil {
				logrus.WithError(err).Warn("password validation failed")
				c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": err})
				return
			}
		}

		if !cacheHit && !shouldCheckDeviceLimit {
			m.Cache.Set(cacheKey, publicCollectionSummary, cache.DefaultExpiration)
		}

		publicCtx := ente.PublicAccessContext{
			ID:            publicCollectionSummary.ID,
			IP:            clientIP,
			UserAgent:     userAgent,
			CollectionID:  publicCollectionSummary.CollectionID,
			EnableComment: publicCollectionSummary.EnableComment,
		}
		c.Set(auth.PublicAccessKey, publicCtx)

		if err := m.attachAnonIdentity(c, publicCtx.CollectionID); err != nil {
			status := http.StatusInternalServerError
			switch {
			case errors.Is(err, ente.ErrAuthenticationRequired):
				status = http.StatusUnauthorized
			case errors.Is(err, ente.ErrPermissionDenied):
				status = http.StatusForbidden
			case errors.Is(err, ente.ErrBadRequest):
				status = http.StatusBadRequest
			}
			c.AbortWithStatusJSON(status, gin.H{"error": err.Error()})
			return
		}

		c.Next()
	}
}

func (m *CollectionLinkMiddleware) checkDeviceLimit(c *gin.Context, accessToken string,
	collectionSummary ente.PublicCollectionSummary, ip string, ua string) (string, bool, error) {
	linkID := strconv.FormatInt(collectionSummary.ID, 10)
	linkDeviceToken := auth.GetLinkDeviceToken(c)
	if linkDeviceToken != "" {
		claim, err := public2.ValidateLinkDeviceToken(m.PublicCollectionCtrl.JwtSecret, linkDeviceToken, public2.LinkDeviceScopeCollection, linkID, accessToken)
		if err == nil {
			if claim.ExpiryTime-time.Microseconds() < public2.LinkDeviceTokenRefreshBefore {
				token, _, tokenErr := public2.NewLinkDeviceToken(m.PublicCollectionCtrl.JwtSecret, public2.LinkDeviceScopeCollection, linkID, accessToken, collectionSummary.ValidTill)
				return token, false, stacktrace.Propagate(tokenErr, "")
			}
			return "", false, nil
		}
	}
	reached, err := m.isDeviceLimitReached(c, collectionSummary, ip, ua)
	if err != nil || reached {
		return "", reached, stacktrace.Propagate(err, "")
	}
	token, _, err := public2.NewLinkDeviceToken(m.PublicCollectionCtrl.JwtSecret, public2.LinkDeviceScopeCollection, linkID, accessToken, collectionSummary.ValidTill)
	return token, false, stacktrace.Propagate(err, "")
}

func shouldCheckCollectionLinkDeviceLimit(reqPath string) bool {
	// Device admission for public collections is intentionally tied to the two
	// metadata endpoints used as the browser entry/refresh points. Other routes
	// (download/upload/social) continue to use the already-admitted session.
	return reqPath == "/public-collection/info" ||
		reqPath == "/public-collection/diff"
}

// validateOwnersSubscription checks if the owner has an active subscription.
// Returns (isFreeUser, error) where isFreeUser is true if user is on free plan but has active subscription.
func (m *CollectionLinkMiddleware) validateOwnersSubscription(c *gin.Context, cID int64) (bool, error) {
	userID, err := m.CollectionRepo.GetOwnerID(cID)
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}

	isFreeUser := false
	err = m.BillingCtrl.HasActiveSelfOrFamilySubscription(userID, true)
	if err != nil {
		if !errors.Is(err, ente.ErrSharingDisabledForFreeAccounts) {
			return false, stacktrace.Propagate(err, "failed to validate owners subscription")
		}
		isFreeUser = true
		// Free user - check if they have active subscription (not expired)
		if err = m.BillingCtrl.HasActiveSelfOrFamilySubscription(userID, false); err != nil {
			return false, stacktrace.Propagate(err, "failed to validate owners subscription")
		}
	}

	return isFreeUser, m.validateOrigin(c, userID)
}

func (m *CollectionLinkMiddleware) isDeviceLimitReached(ctx context.Context,
	collectionSummary ente.PublicCollectionSummary, ip string, ua string) (bool, error) {
	// skip deviceLimit check & record keeping for requests via CF worker
	if network.IsCFWorkerIP(ip) {
		return false, nil
	}

	sharedID := collectionSummary.ID
	hasAccessedInPast, err := m.CollectionLinkRepo.AccessedInPast(ctx, sharedID, ip, ua)
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	// if the device has accessed the url in the past, let it access it now as well, irrespective of device limit.
	if hasAccessedInPast {
		return false, nil
	}
	count, err := m.CollectionLinkRepo.GetUniqueAccessCount(ctx, sharedID)
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to get unique access count")
	}

	deviceLimit := int64(collectionSummary.DeviceLimit)
	if deviceLimit == public2.DeviceLimitThreshold {
		deviceLimit = public2.DeviceLimitThresholdMultiplier * public2.DeviceLimitThreshold
	}

	if count >= public2.DeviceLimitWarningThreshold && count%200 == 0 {
		m.DiscordController.NotifyPotentialAbuse(
			fmt.Sprintf("Album exceeds warning threshold: {CollectionID: %d, ShareID: %d, DeviceCount: %d}",
				collectionSummary.CollectionID, collectionSummary.ID, count))
	}

	if deviceLimit > 0 && count >= deviceLimit {
		return true, nil
	}
	err = m.CollectionLinkRepo.RecordAccessHistory(ctx, sharedID, ip, ua)
	return false, stacktrace.Propagate(err, "failed to record access history")
}

// validatePassword will verify if the user is provided correct password for the public album
func (m *CollectionLinkMiddleware) validatePassword(c *gin.Context, reqPath string,
	collectionSummary ente.PublicCollectionSummary) error {
	// /public-collection/info is allowed before password unlock so clients can
	// fetch the KDF parameters needed to verify the password. Device-limit
	// admission is intentionally still applied to this public entrypoint.
	if slices.Contains(passwordWhiteListedURLs, reqPath) {
		return nil
	}
	accessTokenJWT := auth.GetAccessTokenJWT(c)
	if accessTokenJWT == "" {
		return ente.ErrAuthenticationRequired
	}
	return m.PublicCollectionCtrl.ValidateJWTToken(c, accessTokenJWT, *collectionSummary.PassHash)
}

func (m *CollectionLinkMiddleware) validateOrigin(c *gin.Context, ownerID int64) error {
	origin := c.Request.Header.Get("Origin")
	embedAlbumsOrigin := viper.GetString("apps.embed-albums")

	if origin == "" ||
		origin == viper.GetString("apps.public-albums") ||
		origin == embedAlbumsOrigin ||
		// Keep old embedded iframes working after moving the default embed app
		// origin to embed.ente.com. Custom embed origins should not inherit this.
		(embedAlbumsOrigin == "https://embed.ente.com" && origin == "https://embed.ente.io") ||
		origin == viper.GetString("apps.public-locker") ||
		network.IsLoopbackOrigin(origin) {
		return nil
	}
	reqId := requestid.Get(c)
	logger := logrus.WithFields(logrus.Fields{
		"ownerID": ownerID,
		"req_id":  reqId,
		"origin":  origin,
	})
	alertMessage := fmt.Sprintf("custom domain %s", reqId)
	domain, err := m.RemoteStoreRepo.GetEffectiveDomain(c, ownerID)
	if err != nil {
		logger.WithError(err).Error("domainFetchFailed")
		return nil
	}
	if domain == nil || *domain == "" {
		logger.Warn("domainNotConfigured")
		return ente.NewPermissionDeniedError("no custom domain configured")
	}
	parse, err := url.Parse(origin)
	if err != nil {
		logger.WithError(err).Error("originParseFailedL")
		return ente.NewPermissionDeniedError("unknown custom domain")
	}
	asciiDomain, err := idna.ToASCII(*domain)
	if err != nil {
		logger.WithError(err).Error("domainToASCIIFailed")
		m.DiscordController.NotifyPotentialAbuse(alertMessage + " - domainToASCIIFailed")
		return ente.NewPermissionDeniedError("unknown custom domain")
	}
	if !strings.EqualFold(parse.Hostname(), asciiDomain) {
		logger.Warnf("domainMismatch: domain %s (ascii %s) vs originHost %s", *domain, asciiDomain, parse.Hostname())
		m.DiscordController.NotifyPotentialAbuse(alertMessage + " - domainMismatch")
		return ente.NewPermissionDeniedError("unknown custom domain")
	}
	return nil
}

func (m *CollectionLinkMiddleware) attachAnonIdentity(c *gin.Context, collectionID int64) error {
	if len(m.AnonIdentitySecret) == 0 {
		return nil
	}
	token := strings.TrimSpace(c.GetHeader("X-Anon-User-Token"))
	if token == "" {
		return nil
	}
	claim, err := ente.ParseAnonymousIdentityToken(m.AnonIdentitySecret, token)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	anonID := claim.Subject
	if anonID == "" {
		return ente.ErrAuthenticationRequired
	}
	if m.AnonUsersRepo != nil {
		anonUser, err := m.AnonUsersRepo.GetByID(c, anonID)
		if err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return ente.ErrAuthenticationRequired
			}
			return stacktrace.Propagate(err, "")
		}
		if anonUser.CollectionID != collectionID {
			return ente.ErrPermissionDenied
		}
	}
	auth.SetPublicAnonUserID(c, anonID)
	return nil
}

func computeHashKeyForList(list []string, delim string) string {
	var buffer bytes.Buffer
	for i := range list {
		buffer.WriteString(list[i])
		buffer.WriteString(delim)
	}
	sha := sha256.Sum256(buffer.Bytes())
	return fmt.Sprintf("%x\n", sha)
}
