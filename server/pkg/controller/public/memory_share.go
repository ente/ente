package public

import (
	"context"
	"database/sql"
	"errors"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/sirupsen/logrus"
)

// MemoryShareController handles public memory share operations
type MemoryShareController struct {
	Repo           *repo.MemoryShareRepository
	FileRepo       *repo.FileRepository
	CollectionRepo *repo.CollectionRepository
	FileController *controller.FileController
}

// NewMemoryShareController creates a new public memory share controller
func NewMemoryShareController(
	repo *repo.MemoryShareRepository,
	fileRepo *repo.FileRepository,
	collectionRepo *repo.CollectionRepository,
	fileController *controller.FileController,
) *MemoryShareController {
	return &MemoryShareController{
		Repo:           repo,
		FileRepo:       fileRepo,
		CollectionRepo: collectionRepo,
		FileController: fileController,
	}
}

// GetPublicMemoryShare retrieves a public memory share by access token
func (c *MemoryShareController) GetPublicMemoryShare(ctx context.Context, accessToken string) (*ente.MemoryShare, error) {
	share, err := c.Repo.GetByAccessToken(ctx, accessToken)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to get memory share")
	}
	if share.IsDeleted {
		return nil, stacktrace.Propagate(ente.ErrNotFound, "memory share is deleted")
	}
	if ente.IsMemoryShareExpired(share.CreatedAt) {
		return nil, &ente.ApiError{Message: "memory share has expired", HttpStatusCode: 410}
	}
	return share, nil
}

// GetPublicFiles retrieves all files in a public memory share
func (c *MemoryShareController) GetPublicFiles(ctx context.Context, shareID int64) (*ente.PublicMemoryShareFilesResponse, error) {
	shareFiles, err := c.Repo.GetFiles(ctx, shareID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to get memory share files")
	}

	if len(shareFiles) == 0 {
		return &ente.PublicMemoryShareFilesResponse{Files: []ente.PublicMemoryShareFile{}}, nil
	}

	publicFiles := make([]ente.PublicMemoryShareFile, 0, len(shareFiles))

	for _, sf := range shareFiles {
		collectionCount, err := c.CollectionRepo.GetCollectionCount(sf.FileID)
		if err != nil {
			return nil, stacktrace.Propagate(err, "failed to verify file activity")
		}
		if collectionCount == 0 {
			logrus.WithField("fileID", sf.FileID).Info("skipping inactive file")
			continue
		}

		file, err := c.FileRepo.GetFileAttributes(sf.FileID)
		if err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				logrus.WithField("fileID", sf.FileID).Info("skipping deleted file")
				continue
			}
			return nil, stacktrace.Propagate(err, "failed to get file attributes")
		}

		if file.Metadata.EncryptedData == "-" {
			logrus.WithField("fileID", sf.FileID).Info("skipping placeholder file")
			continue
		}

		file.MagicMetadata = nil

		publicFile := ente.PublicMemoryShareFile{
			File:               *file,
			Position:           sf.Position,
			EncryptedKey:       sf.EncryptedKey,
			KeyDecryptionNonce: sf.KeyDecryptionNonce,
		}
		publicFiles = append(publicFiles, publicFile)
	}

	return &ente.PublicMemoryShareFilesResponse{Files: publicFiles}, nil
}

func (c *MemoryShareController) GetAccessibleFileOwnerID(ctx context.Context, shareID int64, fileID int64) (int64, error) {
	exists, ownerID, err := c.Repo.FileExistsInShare(ctx, shareID, fileID)
	if err != nil {
		return 0, stacktrace.Propagate(err, "failed to check file existence")
	}
	if !exists {
		return 0, stacktrace.Propagate(ente.ErrNotFound, "file not found in memory share")
	}

	collectionCount, err := c.CollectionRepo.GetCollectionCount(fileID)
	if err != nil {
		return 0, stacktrace.Propagate(err, "failed to verify file activity")
	}
	if collectionCount == 0 {
		return 0, stacktrace.Propagate(ente.ErrNotFound, "file not available")
	}

	return ownerID, nil
}

// GetPublicFileURL returns a signed URL for accessing a file in a public memory share
func (c *MemoryShareController) GetPublicFileURL(ctx *gin.Context, shareID int64, fileID int64, objType ente.ObjectType) (string, error) {
	_, err := c.GetAccessibleFileOwnerID(ctx, shareID, fileID)
	if err != nil {
		return "", err
	}

	file, err := c.FileRepo.GetFileAttributes(fileID)
	if err != nil {
		return "", stacktrace.Propagate(err, "failed to fetch file attributes")
	}
	if file.Metadata.EncryptedData == "-" {
		return "", stacktrace.Propagate(ente.ErrNotFound, "file not available")
	}

	url, err := c.FileController.GetSignedURLForPublicFile(ctx, fileID, objType)
	if err != nil {
		return "", stacktrace.Propagate(err, "failed to get signed URL")
	}
	return url, nil
}
