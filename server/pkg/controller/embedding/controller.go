package embedding

import (
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/embedding"
	"strconv"
)

type Controller struct {
	Repo                    *embedding.Repository
	ObjectCleanupController *controller.ObjectCleanupController
	QueueRepo               *repo.QueueRepository
	TaskLockingRepo         *repo.TaskLockRepository
	FileRepo                *repo.FileRepository
	HostName                string
	cleanupCronRunning      bool
}

func New(repo *embedding.Repository, objectCleanupController *controller.ObjectCleanupController, queueRepo *repo.QueueRepository, taskLockingRepo *repo.TaskLockRepository, fileRepo *repo.FileRepository, hostName string) *Controller {
	return &Controller{
		Repo:                    repo,
		ObjectCleanupController: objectCleanupController,
		QueueRepo:               queueRepo,
		TaskLockingRepo:         taskLockingRepo,
		FileRepo:                fileRepo,
		HostName:                hostName,
	}
}

func (c *Controller) getEmbeddingObjectPrefix(userID int64, fileID int64) string {
	return strconv.FormatInt(userID, 10) + "/ml-data/" + strconv.FormatInt(fileID, 10) + "/"
}
