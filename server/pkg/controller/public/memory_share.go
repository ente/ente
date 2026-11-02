package public

import (
	"context"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

type MemoryShareController struct {
	Repo           *repo.MemoryShareRepository
	FileRepo       *repo.FileRepository
	CollectionRepo *repo.CollectionRepository
	FileController *controller.FileController
}

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

func (c *MemoryShareController) GetPublicFiles(ctx context.Context, shareID int64) (*ente.PublicMemoryShareFilesResponse, error) {
	publicFiles, err := c.Repo.GetPublicFiles(ctx, shareID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to get memory share files")
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
