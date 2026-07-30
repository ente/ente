package memory_share

import (
	"context"
	"errors"
	"strings"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller/access"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/lithammer/shortuuid/v3"
)

const (
	AccessTokenLength = 10
)

// Controller handles memory share operations
type Controller struct {
	Repo       *repo.MemoryShareRepository
	FileRepo   *repo.FileRepository
	AccessCtrl access.Controller
}

// NewController creates a new memory share controller
func NewController(
	repo *repo.MemoryShareRepository,
	fileRepo *repo.FileRepository,
	accessCtrl access.Controller,
) *Controller {
	return &Controller{
		Repo:       repo,
		FileRepo:   fileRepo,
		AccessCtrl: accessCtrl,
	}
}

// Create creates a new memory share
func (c *Controller) Create(ctx *gin.Context, userID int64, req ente.CreateMemoryShareRequest) (*ente.CreateMemoryShareResponse, error) {
	shareType := req.Type
	if shareType == "" {
		shareType = ente.MemoryShareTypeShare
	}
	if shareType != ente.MemoryShareTypeShare &&
		shareType != ente.MemoryShareTypeLane {
		return nil, stacktrace.Propagate(ente.ErrBadRequest, "invalid memory share type")
	}

	fileIDs := make([]int64, len(req.Files))
	for i, f := range req.Files {
		fileIDs[i] = f.FileID
	}

	err := c.AccessCtrl.CanAccessFile(ctx, &access.CanAccessFileParams{
		ActorUserID: userID,
		FileIDs:     fileIDs,
	})
	if err != nil {
		if errors.Is(err, ente.ErrPermissionDenied) {
			return nil, stacktrace.Propagate(ente.ErrPermissionDenied, "user cannot access all files")
		}
		return nil, stacktrace.Propagate(err, "failed to validate file access")
	}

	ownerMap, err := c.FileRepo.GetOwnerToFileIDsMap(ctx, fileIDs)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to get file ownership map")
	}

	fileOwnerMap := make(map[int64]int64)
	for ownerID, fIDs := range ownerMap {
		for _, fid := range fIDs {
			fileOwnerMap[fid] = ownerID
		}
	}

	if len(fileOwnerMap) != len(fileIDs) {
		return nil, stacktrace.Propagate(ente.ErrBadRequest, "one or more file IDs do not exist")
	}

	shareFiles := make([]ente.MemoryShareFile, len(req.Files))
	now := time.Microseconds()
	for i, f := range req.Files {
		position := int64(i)
		if f.Position != nil {
			if *f.Position < 0 {
				return nil, stacktrace.Propagate(ente.ErrBadRequest, "position cannot be negative")
			}
			position = *f.Position
		}
		shareFiles[i] = ente.MemoryShareFile{
			FileID:             f.FileID,
			FileOwnerID:        fileOwnerMap[f.FileID],
			Position:           position,
			EncryptedKey:       f.EncryptedKey,
			KeyDecryptionNonce: f.KeyDecryptionNonce,
			CreatedAt:          now,
		}
	}

	var share ente.MemoryShare
	for range 5 {
		// Retry on rare access-token collisions to match collection/file link behavior.
		accessToken := strings.ToUpper(shortuuid.New()[0:AccessTokenLength])

		share = ente.MemoryShare{
			UserID:             userID,
			Type:               shareType,
			MemoryHash:         req.MemoryHash,
			MetadataCipher:     req.MetadataCipher,
			MetadataNonce:      req.MetadataNonce,
			EncryptedKey:       req.EncryptedKey,
			KeyDecryptionNonce: req.KeyDecryptionNonce,
			AccessToken:        accessToken,
		}

		share, err = c.Repo.CreateWithFiles(ctx, share, shareFiles)
		if errors.Is(err, ente.ErrAccessTokenInUse) {
			continue
		}
		if err != nil {
			return nil, stacktrace.Propagate(err, "failed to create memory share")
		}

		return &ente.CreateMemoryShareResponse{MemoryShare: share}, nil
	}

	return nil, stacktrace.Propagate(ente.ErrAccessTokenInUse, "failed to generate unique access token")
}

func (c *Controller) List(ctx context.Context, userID int64) (*ente.ListMemorySharesResponse, error) {
	shares, err := c.Repo.GetByUserID(ctx, userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to list memory shares")
	}
	if shares == nil {
		shares = []ente.MemoryShare{}
	}
	return &ente.ListMemorySharesResponse{MemoryShares: shares}, nil
}

func (c *Controller) Delete(ctx context.Context, userID int64, shareID int64) error {
	err := c.Repo.Delete(ctx, shareID, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to delete memory share")
	}
	return nil
}

func (c *Controller) GetByID(ctx context.Context, userID int64, shareID int64) (*ente.MemoryShare, error) {
	share, err := c.Repo.GetByID(ctx, shareID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to get memory share")
	}
	if share.UserID != userID {
		return nil, stacktrace.Propagate(ente.ErrPermissionDenied, "user does not own this share")
	}
	if share.IsDeleted || ente.IsMemoryShareExpired(share.CreatedAt) {
		return nil, stacktrace.Propagate(ente.ErrNotFound, "memory share not available")
	}
	return share, nil
}
