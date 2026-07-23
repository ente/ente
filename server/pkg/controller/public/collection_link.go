package public

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller"
	emailCtrl "github.com/ente/museum/pkg/controller/email"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/public"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/lithammer/shortuuid/v3"
	"github.com/sirupsen/logrus"
)

const (
	AccessTokenLength = 10

	// DeviceLimitThreshold represents number of unique devices which can access a shared collection. (ip + user agent)
	// is treated as unique device
	DeviceLimitThreshold = 50

	DeviceLimitThresholdMultiplier = 10

	DeviceLimitWarningThreshold = 2000

	// FreeUserDeviceLimit is the hardcoded device limit for free users
	FreeUserDeviceLimit = 5
)

// CollectionLinkController controls share collection operations
type CollectionLinkController struct {
	FileController        *controller.FileController
	EmailNotificationCtrl *emailCtrl.EmailNotificationController
	CollectionLinkRepo    *public.CollectionLinkRepo
	FileLinkRepo          *public.FileLinkRepository
	CollectionRepo        *repo.CollectionRepository
	UserRepo              *repo.UserRepository
	JwtSecret             []byte
}

func (c *CollectionLinkController) CreateLink(ctx *gin.Context, req ente.CreatePublicAccessTokenRequest) (ente.PublicURL, error) {
	app := auth.GetApp(ctx)
	for range 5 {
		accessToken := strings.ToUpper(shortuuid.New()[0:AccessTokenLength])
		err := c.CollectionLinkRepo.
			Insert(ctx, req.CollectionID, accessToken, req.ValidTill, req.DeviceLimit, req.EnableCollect, req.EnableComment, req.EnableJoin)
		if errors.Is(err, ente.ErrAccessTokenInUse) {
			continue
		}
		if err != nil {
			if errors.Is(err, ente.ErrActiveLinkAlreadyExists) {
				collectionToPubUrlMap, err2 := c.CollectionLinkRepo.GetCollectionToActivePublicURLMap(ctx, []int64{req.CollectionID}, app)
				if err2 != nil {
					return ente.PublicURL{}, stacktrace.Propagate(err2, "")
				}
				if publicUrls, ok := collectionToPubUrlMap[req.CollectionID]; ok {
					if len(publicUrls) > 0 {
						return publicUrls[0], nil
					}
				}
				// ideally we should never reach here
				return ente.PublicURL{}, stacktrace.NewError("Unexpected state")
			}
			return ente.PublicURL{}, stacktrace.Propagate(err, "")
		}
		enableJoin := false
		if req.EnableJoin != nil {
			enableJoin = *req.EnableJoin
		}

		response := ente.PublicURL{
			URL:             c.CollectionLinkRepo.GetAlbumUrl(app, accessToken),
			ValidTill:       req.ValidTill,
			DeviceLimit:     req.DeviceLimit,
			EnableDownload:  true,
			EnableCollect:   req.EnableCollect,
			EnableComment:   req.EnableComment,
			EnableJoin:      enableJoin,
			PasswordEnabled: false,
			MinRole:         nil,
		}
		return response, nil
	}

	return ente.PublicURL{}, stacktrace.Propagate(ente.ErrAccessTokenInUse, "failed to generate unique access token for collection link")
}

func (c *CollectionLinkController) GetActiveCollectionLinkToken(ctx context.Context, collectionID int64) (ente.CollectionLinkRow, error) {
	return c.CollectionLinkRepo.GetActiveCollectionLinkRow(ctx, collectionID)
}

func (c *CollectionLinkController) CreateFile(ctx *gin.Context, file ente.File, app ente.App) (ente.File, error) {
	collection, err := c.GetPublicCollection(ctx, true)
	if err != nil {
		return ente.File{}, stacktrace.Propagate(err, "")
	}
	collectionOwnerID := collection.Owner.ID
	// Do not let any update happen via public Url
	file.ID = 0
	file.OwnerID = collectionOwnerID
	file.UpdationTime = time.Microseconds()
	file.IsDeleted = false
	createdFile, err := c.FileController.Create(ctx, collectionOwnerID, file, ctx.Request.UserAgent(), app)
	if err != nil {
		return ente.File{}, stacktrace.Propagate(err, "")
	}

	// Note: Stop sending email notification for public collection till
	// we add in-app setting to enable/disable email notifications
	//go c.EmailNotificationCtrl.OnFilesCollected(file.OwnerID)
	return createdFile, nil
}

// Disable all public accessTokens generated for the given cID till date.
func (c *CollectionLinkController) Disable(ctx context.Context, cID int64) error {
	err := c.CollectionLinkRepo.DisableSharing(ctx, cID)
	return stacktrace.Propagate(err, "")
}

func (c *CollectionLinkController) UpdateSharedUrl(ctx *gin.Context, req ente.UpdatePublicAccessTokenRequest) (ente.PublicURL, error) {
	publicCollectionToken, err := c.CollectionLinkRepo.GetActiveCollectionLinkRow(ctx, req.CollectionID)
	if err != nil {
		return ente.PublicURL{}, err
	}
	if req.ValidTill != nil {
		publicCollectionToken.ValidTill = *req.ValidTill
	}
	if req.DeviceLimit != nil {
		publicCollectionToken.DeviceLimit = *req.DeviceLimit
	}
	if req.PassHash != nil && req.Nonce != nil && req.OpsLimit != nil && req.MemLimit != nil {
		publicCollectionToken.PassHash = req.PassHash
		publicCollectionToken.Nonce = req.Nonce
		publicCollectionToken.OpsLimit = req.OpsLimit
		publicCollectionToken.MemLimit = req.MemLimit
	} else if req.DisablePassword != nil && *req.DisablePassword {
		publicCollectionToken.PassHash = nil
		publicCollectionToken.Nonce = nil
		publicCollectionToken.OpsLimit = nil
		publicCollectionToken.MemLimit = nil
	}
	if req.EnableDownload != nil {
		publicCollectionToken.EnableDownload = *req.EnableDownload
	}
	if req.EnableCollect != nil {
		publicCollectionToken.EnableCollect = *req.EnableCollect
	}
	if req.EnableComment != nil {
		publicCollectionToken.EnableComment = *req.EnableComment
	}
	if req.EnableJoin != nil {
		publicCollectionToken.EnableJoin = *req.EnableJoin
	}
	if req.MinRole != nil {
		role := *req.MinRole
		rolePtr := role
		publicCollectionToken.MinRole = &rolePtr
	}
	err = c.CollectionLinkRepo.UpdatePublicCollectionToken(ctx, publicCollectionToken)
	if err != nil {
		return ente.PublicURL{}, stacktrace.Propagate(err, "")
	}
	app := auth.GetApp(ctx)
	return ente.PublicURL{
		URL:             c.CollectionLinkRepo.GetAlbumUrl(app, publicCollectionToken.Token),
		DeviceLimit:     publicCollectionToken.DeviceLimit,
		ValidTill:       publicCollectionToken.ValidTill,
		EnableDownload:  publicCollectionToken.EnableDownload,
		EnableCollect:   publicCollectionToken.EnableCollect,
		EnableComment:   publicCollectionToken.EnableComment,
		EnableJoin:      publicCollectionToken.EnableJoin,
		MinRole:         publicCollectionToken.MinRole,
		PasswordEnabled: publicCollectionToken.PassHash != nil && *publicCollectionToken.PassHash != "",
		Nonce:           publicCollectionToken.Nonce,
		MemLimit:        publicCollectionToken.MemLimit,
		OpsLimit:        publicCollectionToken.OpsLimit,
	}, nil
}

// VerifyPassword verifies if the user has provided correct pw hash. If yes, it returns a signed jwt token which can be
// used by the client to pass in other requests for public collection.
// Having a separate endpoint for password validation allows us to easily rate-limit the attempts for brute-force
// attack for guessing password.
func (c *CollectionLinkController) VerifyPassword(ctx *gin.Context, req ente.VerifyPasswordRequest) (*ente.VerifyPasswordResponse, error) {
	accessContext := auth.MustGetPublicAccessContext(ctx)
	collectionLinkRow, err := c.CollectionLinkRepo.GetActiveCollectionLinkRow(ctx, accessContext.CollectionID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to get public collection info")
	}
	return verifyPassword(c.JwtSecret, collectionLinkRow.PassHash, req)
}

func (c *CollectionLinkController) ValidateJWTToken(ctx *gin.Context, jwtToken string, passwordHash string) error {
	return validateJWTToken(c.JwtSecret, jwtToken, passwordHash)
}

func (c *CollectionLinkController) HandleAccountDeletion(ctx context.Context, userID int64, logger *logrus.Entry) error {
	logger.Info("updating public collection on account deletion")
	collectionIDs, err := c.CollectionLinkRepo.GetActivePublicTokenForUser(ctx, userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	logger.WithField("cIDs", collectionIDs).Info("disable public tokens due to account deletion")
	for _, collectionID := range collectionIDs {
		err = c.Disable(ctx, collectionID)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
	}
	return c.FileLinkRepo.DisableLinksForUser(ctx, userID)
}

// GetPublicCollection will return collection info for a public url.
// is mustAllowCollect is set to true but the underlying collection doesn't allow uploading
func (c *CollectionLinkController) GetPublicCollection(ctx *gin.Context, mustAllowCollect bool) (ente.Collection, error) {
	accessContext := auth.MustGetPublicAccessContext(ctx)
	collection, err := c.CollectionRepo.Get(accessContext.CollectionID)
	if err != nil {
		return ente.Collection{}, stacktrace.Propagate(err, "")
	}
	if collection.IsDeleted {
		return ente.Collection{}, stacktrace.Propagate(ente.ErrNotFound, "collection is deleted")
	}
	// hide redundant/private information
	collection.Sharees = nil
	collection.MagicMetadata = nil
	publicURLsWithLimitedInfo := make([]ente.PublicURL, 0)
	for _, publicUrl := range collection.PublicURLs {
		publicURLsWithLimitedInfo = append(publicURLsWithLimitedInfo, ente.PublicURL{
			EnableDownload:  publicUrl.EnableDownload,
			EnableCollect:   publicUrl.EnableCollect,
			EnableComment:   publicUrl.EnableComment,
			PasswordEnabled: publicUrl.PasswordEnabled,
			Nonce:           publicUrl.Nonce,
			MemLimit:        publicUrl.MemLimit,
			OpsLimit:        publicUrl.OpsLimit,
			EnableJoin:      publicUrl.EnableJoin,
		})
	}
	collection.PublicURLs = publicURLsWithLimitedInfo
	if mustAllowCollect {
		if len(publicURLsWithLimitedInfo) != 1 {
			errorMsg := fmt.Sprintf("Unexpected number of public urls: %d", len(publicURLsWithLimitedInfo))
			return ente.Collection{}, stacktrace.Propagate(ente.NewInternalError(errorMsg), "")
		}
		if !publicURLsWithLimitedInfo[0].EnableCollect {
			return ente.Collection{}, stacktrace.Propagate(&ente.ErrPublicCollectDisabled, "")
		}
	}
	return collection, nil
}
