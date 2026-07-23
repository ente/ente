package access

import (
	"github.com/ente/museum/pkg/repo"
	"github.com/gin-gonic/gin"
)

// Controller exposes helper methods to perform access checks while fetching or editing
// any entity.
type Controller interface {
	GetCollection(ctx *gin.Context, req *GetCollectionParams) (*GetCollectionResponse, error)
	VerifyFileOwnership(ctx *gin.Context, req *VerifyFileOwnershipParams) error
	CanAccessFile(ctx *gin.Context, req *CanAccessFileParams) error
}

// controllerImpl implements Controller
type controllerImpl struct {
	FileRepo       *repo.FileRepository
	CollectionRepo *repo.CollectionRepository
}

// https://stackoverflow.com/a/33089540/546896
var _ Controller = (*controllerImpl)(nil) // Verify that *T implements I.
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
