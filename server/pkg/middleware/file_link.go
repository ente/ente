package middleware

import (
	"context"
	"fmt"
	"net/http"
	"slices"

	publicCtrl "github.com/ente/museum/pkg/controller/public"
	"github.com/ente/museum/pkg/repo/public"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/controller/discord"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/network"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/patrickmn/go-cache"
	"github.com/sirupsen/logrus"
)

var filePasswordWhiteListedURLs = []string{"/file-link/pass-info", "/file-link/verify-password"}

// FileLinkMiddleware intercepts and authenticates incoming requests
type FileLinkMiddleware struct {
	FileLinkRepo      *public.FileLinkRepository
	FileLinkCtrl      *publicCtrl.FileLinkController
	Cache             *cache.Cache
	BillingCtrl       *controller.BillingController
	DiscordController *discord.DiscordController
}

// Authenticate returns a middle ware that extracts the `X-Auth-Access-Token`
// within the header of a request and uses it to validate the access token and set the
// ente.PublicAccessContext with auth.PublicAccessKey as key
func (m *FileLinkMiddleware) Authenticate(urlSanitizer func(_ *gin.Context) string) gin.HandlerFunc {
	return func(c *gin.Context) {
		accessToken := auth.GetAccessToken(c)
		if accessToken == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing accessToken", "context": "file_link"})
			return
		}
		clientIP := network.GetClientIP(c)
		userAgent := c.GetHeader("User-Agent")
		reqPath := urlSanitizer(c)
		shouldCheckDeviceLimit := shouldCheckFileLinkDeviceLimit(reqPath)
		passwordValidated := false

		cacheKey := computeHashKeyForList([]string{accessToken, clientIP, userAgent}, ":")
		var cachedValue interface{}
		cacheHit := false
		if !shouldCheckDeviceLimit {
			cachedValue, cacheHit = m.Cache.Get(cacheKey)
		}
		var fileLinkRow *ente.FileLinkRow
		var err error
		if !cacheHit {
			fileLinkRow, err = m.FileLinkRepo.GetFileUrlRowByToken(c, accessToken)
			if err != nil {
				logrus.WithError(err).Info("failed to get file link row by token")
				c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
				return
			}
			if fileLinkRow.IsDisabled {
				c.AbortWithStatusJSON(http.StatusGone, gin.H{"error": "disabled token"})
				return
			}
			if fileLinkRow.ValidTill > 0 && // expiry time is defined, 0 indicates no expiry
				fileLinkRow.ValidTill < time.Microseconds() {
				c.AbortWithStatusJSON(http.StatusGone, gin.H{"error": "expired token"})
				return
			}
			if fileLinkRow.PassHash != nil && *fileLinkRow.PassHash != "" {
				if err = m.validatePassword(c, reqPath, fileLinkRow); err != nil {
					logrus.WithError(err).Warn("password validation failed")
					c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": err})
					return
				}
				passwordValidated = true
			}
			if shouldCheckDeviceLimit {
				linkDeviceToken, reached, limitErr := m.checkDeviceLimit(c, accessToken, fileLinkRow, clientIP, userAgent)
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
			fileLinkRow = cachedValue.(*ente.FileLinkRow)
		}

		if fileLinkRow.ValidTill > 0 && // expiry time is defined, 0 indicates no expiry
			fileLinkRow.ValidTill < time.Microseconds() {
			c.AbortWithStatusJSON(http.StatusGone, gin.H{"error": "expired token"})
			return
		}

		// checks password protected public collection
		if !passwordValidated && fileLinkRow.PassHash != nil && *fileLinkRow.PassHash != "" {
			if err = m.validatePassword(c, reqPath, fileLinkRow); err != nil {
				logrus.WithError(err).Warn("password validation failed")
				c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": err})
				return
			}
		}

		if !cacheHit && !shouldCheckDeviceLimit {
			m.Cache.Set(cacheKey, fileLinkRow, cache.DefaultExpiration)
		}

		c.Set(auth.FileLinkAccessKey, &ente.FileLinkAccessContext{
			LinkID:    fileLinkRow.LinkID,
			IP:        clientIP,
			UserAgent: userAgent,
			FileID:    fileLinkRow.FileID,
			OwnerID:   fileLinkRow.OwnerID,
		})
		c.Next()
	}
}

func (m *FileLinkMiddleware) checkDeviceLimit(c *gin.Context, accessToken string,
	fileLinkRow *ente.FileLinkRow, ip string, ua string) (string, bool, error) {
	linkDeviceToken := auth.GetLinkDeviceToken(c)
	if linkDeviceToken != "" {
		claim, err := publicCtrl.ValidateLinkDeviceToken(m.FileLinkCtrl.JwtSecret, linkDeviceToken, publicCtrl.LinkDeviceScopeFile, fileLinkRow.LinkID, accessToken)
		if err == nil {
			if claim.ExpiryTime-time.Microseconds() < publicCtrl.LinkDeviceTokenRefreshBefore {
				token, _, tokenErr := publicCtrl.NewLinkDeviceToken(m.FileLinkCtrl.JwtSecret, publicCtrl.LinkDeviceScopeFile, fileLinkRow.LinkID, accessToken, fileLinkRow.ValidTill)
				return token, false, stacktrace.Propagate(tokenErr, "")
			}
			return "", false, nil
		}
	}
	reached, err := m.isDeviceLimitReached(c, fileLinkRow, ip, ua)
	if err != nil || reached {
		return "", reached, stacktrace.Propagate(err, "")
	}
	token, _, err := publicCtrl.NewLinkDeviceToken(m.FileLinkCtrl.JwtSecret, publicCtrl.LinkDeviceScopeFile, fileLinkRow.LinkID, accessToken, fileLinkRow.ValidTill)
	return token, false, stacktrace.Propagate(err, "")
}

func shouldCheckFileLinkDeviceLimit(reqPath string) bool {
	// File-link admission is currently anchored to /file-link/info, which is the
	// discovery endpoint clients call before fetching the actual blob.
	return reqPath == "/file-link/info"
}

func (m *FileLinkMiddleware) isDeviceLimitReached(ctx context.Context,
	collectionSummary *ente.FileLinkRow, ip string, ua string) (bool, error) {
	// skip deviceLimit check & record keeping for requests via CF worker
	if network.IsCFWorkerIP(ip) {
		return false, nil
	}

	sharedID := collectionSummary.LinkID
	hasAccessedInPast, err := m.FileLinkRepo.AccessedInPast(ctx, sharedID, ip, ua)
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	// if the device has accessed the url in the past, let it access it now as well, irrespective of device limit.
	if hasAccessedInPast {
		return false, nil
	}
	count, err := m.FileLinkRepo.GetUniqueAccessCount(ctx, sharedID)
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to get unique access count")
	}

	deviceLimit := int64(collectionSummary.DeviceLimit)
	if deviceLimit == publicCtrl.DeviceLimitThreshold {
		deviceLimit = publicCtrl.DeviceLimitThresholdMultiplier * publicCtrl.DeviceLimitThreshold
	}

	if count >= publicCtrl.DeviceLimitWarningThreshold && count%200 == 0 {
		m.DiscordController.NotifyPotentialAbuse(
			fmt.Sprintf("FileLink exceeds warning threshold: {FileID: %d, ShareID: %s, DeviceCount: %d}",
				collectionSummary.FileID, collectionSummary.LinkID, count))
	}

	if deviceLimit > 0 && count >= deviceLimit {
		return true, nil
	}
	err = m.FileLinkRepo.RecordAccessHistory(ctx, sharedID, ip, ua)
	return false, stacktrace.Propagate(err, "failed to record access history")
}

// validatePassword will verify if the user is provided correct password for the public album
func (m *FileLinkMiddleware) validatePassword(
	c *gin.Context,
	reqPath string,
	fileLinkRow *ente.FileLinkRow,
) error {
	accessTokenJWT := auth.GetAccessTokenJWT(c)
	if accessTokenJWT == "" {
		if slices.Contains(filePasswordWhiteListedURLs, reqPath) {
			return nil
		}
		return &ente.ErrPassProtectedResource
	}
	return m.FileLinkCtrl.ValidateJWTToken(c, accessTokenJWT, *fileLinkRow.PassHash)
}
