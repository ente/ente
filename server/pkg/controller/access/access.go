package access

import (
	"github.com/ente/museum/pkg/repo"
	"github.com/gin-gonic/gin"
)

type Controller interface {
	GetCollection(ctx *gin.Context, req *GetCollectionParams) (*GetCollectionResponse, error)
	VerifyFileOwnership(ctx *gin.Context, req *VerifyFileOwnershipParams) error
	CanAccessFile(ctx *gin.Context, req *CanAccessFileParams) error
}

type controllerImpl struct {
	FileRepo       *repo.FileRepository
	CollectionRepo *repo.CollectionRepository
}

var _ Controller = (*controllerImpl)(nil)
var _ Controller = controllerImpl{}

func NewAccessController(
	collRepo *repo.CollectionRepository,
	fileRepo *repo.FileRepository,
) Controller {
	comp := &controllerImpl{
		CollectionRepo: collRepo,
		FileRepo:       fileRepo,
	}
	return comp
}
