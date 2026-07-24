package data_cleanup

import (
	"context"
	"errors"
	"fmt"

	"github.com/ente/museum/ente"
	entity "github.com/ente/museum/ente/data_cleanup"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/datacleanup"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	log "github.com/sirupsen/logrus"
)

type DeleteUserCleanupController struct {
	Repo           *datacleanup.Repository
	UserRepo       *repo.UserRepository
	CollectionRepo *repo.CollectionRepository
	TaskLockRepo   *repo.TaskLockRepository
	TrashRepo      *repo.TrashRepository
	UsageRepo      *repo.UsageRepository
	SpaceDataRepo  SpaceDataRepo
	running        bool
	HostName       string
}

type SpaceDataRepo interface {
	DeleteUserData(ctx context.Context, userID int64) error
}

const (
	// nextStageDelayInHoursOnError is number of afters after which next attempt should be made to process
	// current stage.
	nextStageDelayInHoursOnError = 2

	// maximum number of storage check attempt before moving to the next stage.
	maxStorageCheckAttempt = 10
)

// DeleteDataCron delete trashed files which are in trash since repo.TrashDurationInDays
func (c *DeleteUserCleanupController) DeleteDataCron() {
	if c.running {
		log.Info("Already running DeleteDataCron, skipping cron")
		return
	}
	c.running = true
	defer func() {
		c.running = false
	}()

	ctx := context.Background()
	items, err := c.Repo.GetItemsPendingCompletion(ctx, 100)
	if err != nil {
		log.WithError(err).Info("Failed to get items for cleanup")
		return
	}
	if len(items) > 0 {
		log.WithField("count", len(items)).Info("Found pending items")
		for _, item := range items {
			c.deleteUserData(ctx, item)
		}
	}

}

func (c *DeleteUserCleanupController) deleteUserData(ctx context.Context, item *entity.DataCleanup) {
	logger := log.WithFields(log.Fields{
		"user_id":       item.UserID,
		"stage":         item.Stage,
		"attempt_count": item.StageAttemptCount,
		"flow":          "delete_user_data",
	})
	lockName := fmt.Sprintf("delete_user_data-%d", item.UserID)
	lockStatus, err := c.TaskLockRepo.AcquireLock(lockName, time.MicrosecondsAfterHours(1), c.HostName)
	if err != nil || !lockStatus {
		if err != nil {
			logger.Error("error while acquiring lock")
		} else {
			logger.Warn("lock is already head by another instance")
		}
		return
	}
	defer func() {
		releaseErr := c.TaskLockRepo.ReleaseLock(lockName)
		if releaseErr != nil {
			logger.WithError(releaseErr).Error("Error while releasing lock")
		}
	}()

	logger.Info(fmt.Sprintf("Delete data for stage %s", item.Stage))

	switch item.Stage {
	case entity.Scheduled:
		err = c.startCleanup(ctx, item)
	case entity.Collection:
		err = c.deleteCollections(ctx, item)
	case entity.Trash:
		err = c.emptyTrash(ctx, item)
	case entity.Storage:
		err = c.storageCheck(ctx, item)
	default:
		err = fmt.Errorf("unexpected stage %s", item.Stage)
	}
	if err != nil {
		logger.WithError(err).Error("error while processing data deletion")
		err2 := c.Repo.ScheduleNextAttemptAfterNHours(ctx, item.UserID, nextStageDelayInHoursOnError)
		if err2 != nil {
			logger.Error(err)
			return
		}
	}

}

// startClean up will just verify that user
func (c *DeleteUserCleanupController) startCleanup(ctx context.Context, item *entity.DataCleanup) error {
	deleted, err := c.isDeleted(ctx, item)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if !deleted {
		return nil
	}
	// move to next stage for deleting collection
	return c.Repo.MoveToNextStage(ctx, item.UserID, entity.Collection, time.Microseconds())
}

// deleteCollection will schedule all the collections for deletion and queue up Trash stage to run after 30 min
func (c *DeleteUserCleanupController) deleteCollections(ctx context.Context, item *entity.DataCleanup) error {
	collectionsMap, err := c.CollectionRepo.GetCollectionIDsOwnedByUser(item.UserID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	for collectionID, isAlreadyDeleted := range collectionsMap {
		if !isAlreadyDeleted {
			// Delete all files in the collection
			err = c.CollectionRepo.ScheduleDelete(collectionID)
			if err != nil {
				return stacktrace.Propagate(err, "error while deleting collection %d", collectionID)
			}
		}
	}
	/* todo: neeraj : verify that all collection delete request are processed before moving to empty trash stage.
	 */
	return c.Repo.MoveToNextStage(ctx, item.UserID, entity.Trash, time.MicrosecondsAfterMinutes(60))
}

func (c *DeleteUserCleanupController) emptyTrash(ctx context.Context, item *entity.DataCleanup) error {
	// Enqueue empty-trash for both apps
	err := c.TrashRepo.EmptyTrash(ctx, item.UserID, time.Microseconds(), ente.Photos)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	err = c.TrashRepo.EmptyTrash(ctx, item.UserID, time.Microseconds(), ente.Locker)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	// schedule storage consumed check for the user after 60min. Trash should ideally get emptied after 60 min
	return c.Repo.MoveToNextStage(ctx, item.UserID, entity.Storage, time.MicrosecondsAfterMinutes(60))
}

func (c *DeleteUserCleanupController) completeCleanup(ctx context.Context, item *entity.DataCleanup) error {
	if c.SpaceDataRepo != nil {
		if err := c.SpaceDataRepo.DeleteUserData(ctx, item.UserID); err != nil {
			return stacktrace.Propagate(err, "failed to delete space data for user")
		}
	}
	err := c.Repo.DeleteTableData(ctx, item.UserID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to delete table data for user")
	}
	return c.Repo.MoveToNextStage(ctx, item.UserID, entity.Completed, time.Microseconds())
}

// storageCheck validates that user's usage is zero after all collections are deleted and trashed files are processed.
// This check act as another data-integrity check for our db. If even after multiple attempts, storage is still not zero
// we mark the clean-up as done.
func (c *DeleteUserCleanupController) storageCheck(ctx context.Context, item *entity.DataCleanup) error {
	usage, err := c.UsageRepo.GetUsage(item.UserID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if usage != 0 {
		// check if trash still has entry
		timeStamp, err2 := c.TrashRepo.GetTimeStampForLatestNonDeletedEntry(item.UserID)
		if err2 != nil {
			return stacktrace.Propagate(err2, "failed to fetch timestamp")
		}
		// no entry in trash
		if timeStamp != nil {
			log.WithFields(log.Fields{
				"user_id":   item.UserID,
				"flow":      "delete_user_data",
				"timeStamp": timeStamp,
			}).Info("trash is not empty")
			// Enqueue empty-trash for both apps
			err = c.TrashRepo.EmptyTrash(ctx, item.UserID, *timeStamp, ente.Photos)
			if err != nil {
				return stacktrace.Propagate(err, "")
			}
			err = c.TrashRepo.EmptyTrash(ctx, item.UserID, *timeStamp, ente.Locker)
			if err != nil {
				return stacktrace.Propagate(err, "")
			}
		} else if item.StageAttemptCount >= maxStorageCheckAttempt {
			// Note: if storage is still not zero after maxStorageCheckAttempt attempts and trash is empty, mark the clean-up as done
			return c.completeCleanup(ctx, item)
		}
		return fmt.Errorf("storage consumed is not zero: %d", usage)
	}
	return c.completeCleanup(ctx, item)
}

func (c *DeleteUserCleanupController) isDeleted(ctx context.Context, item *entity.DataCleanup) (bool, error) {
	u, err := c.UserRepo.Get(item.UserID)
	if err == nil {
		// user is not deleted, double check by verifying email is not empty
		if u.Email != "" {
			if err := c.Repo.RemoveScheduledDeleteIfPresent(ctx, item.UserID); err != nil {
				return false, stacktrace.Propagate(err, "failed to remove scheduled delete entry")
			}
			return false, nil
		}
		return false, stacktrace.Propagate(ente.NewBadRequestWithMessage("User ID is linked to undeleted account"), "")
	}
	if !errors.Is(err, ente.ErrUserDeleted) {
		return false, stacktrace.Propagate(err, "error while getting the user")
	}
	return true, nil
}
