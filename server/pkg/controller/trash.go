package controller

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/google/uuid"
	log "github.com/sirupsen/logrus"
)

type TrashController struct {
	TrashRepo               *repo.TrashRepository
	FileRepo                *repo.FileRepository
	CollectionRepo          *repo.CollectionRepository
	QueueRepo               *repo.QueueRepository
	TaskLockRepo            *repo.TaskLockRepository
	HostName                string
	dropFileMetadataRunning bool
	collectionTrashRunning  bool
	emptyTrashRunning       bool
	deleteAgedTrashRunning  bool
}

func (t *TrashController) GetDiff(userID int64, sinceTime int64, app ente.App) ([]ente.Trash, bool, error) {
	trashFilesDiff, hasMore, err := t.getDiff(userID, sinceTime, repo.TrashDiffLimit, app)
	if err != nil {
		return nil, false, err
	}
	for _, trashFile := range trashFilesDiff {
		if trashFile.IsDeleted {
			trashFile.File.MagicMetadata = nil
			trashFile.File.PubicMagicMetadata = nil
			trashFile.File.Metadata = ente.FileAttributes{}
			trashFile.File.Info = nil
		}
	}
	return trashFilesDiff, hasMore, err
}

// Never split a version across pages. Results may be smaller or larger than
// limit so every row with the boundary timestamp stays together.
func (t *TrashController) getDiff(userID int64, sinceTime int64, limit int, app ente.App) ([]ente.Trash, bool, error) {
	diffLimitPlusOne, err := t.TrashRepo.GetDiff(userID, sinceTime, limit+1, app)
	if err != nil {
		return nil, false, stacktrace.Propagate(err, "")
	}
	if len(diffLimitPlusOne) <= limit {
		return diffLimitPlusOne, false, nil
	}
	lastFileVersion := diffLimitPlusOne[limit].UpdatedAt
	filteredDiffs := t.removeFilesWithVersion(diffLimitPlusOne, lastFileVersion)
	if len(filteredDiffs) > 0 {
		return filteredDiffs, true, nil
	}
	diff, err := t.TrashRepo.GetFilesWithVersion(userID, lastFileVersion, app)
	if err != nil {
		return nil, false, stacktrace.Propagate(err, "")
	}
	return diff, true, nil
}

func (t *TrashController) Delete(ctx context.Context, request ente.DeleteTrashFilesRequest) error {
	err := t.TrashRepo.Delete(ctx, request.OwnerID, request.FileIDs)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}

func (t *TrashController) EmptyTrash(ctx context.Context, userID int64, req ente.EmptyTrashRequest, app ente.App) error {
	err := t.TrashRepo.EmptyTrash(ctx, userID, req.LastUpdatedAt, app)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer t.ProcessEmptyTrashRequests()
	return nil
}

func (t *TrashController) CleanupTrashedCollections() {
	ctxLogger := log.WithFields(log.Fields{
		"flow": "trash_collection",
		"id":   uuid.New().String(),
	})
	item_processed_count := 0
	if t.collectionTrashRunning {
		ctxLogger.Info("Already moving collection to trash, skipping cron")
		return
	}
	t.collectionTrashRunning = true
	defer func() {
		ctxLogger.WithField("items_processed", item_processed_count).Info("cron run finished")
		t.collectionTrashRunning = false
	}()

	itemsV3, err2 := t.QueueRepo.GetItemsReadyForDeletion(repo.TrashCollectionQueueV3, 100)
	if err2 != nil {
		log.Error("Could not fetch from collection trash queue", err2)
		return
	}
	item_processed_count += len(itemsV3)
	for _, item := range itemsV3 {
		t.trashCollection(item, repo.TrashCollectionQueueV3, ctxLogger)
	}
}

func (t *TrashController) ProcessEmptyTrashRequests() {
	if t.emptyTrashRunning {
		log.Info("Already processing empty trash requests, skipping cron")
		return
	}
	t.emptyTrashRunning = true
	defer func() {
		t.emptyTrashRunning = false
	}()
	items, err := t.QueueRepo.GetItemsReadyForDeletion(repo.TrashEmptyQueue, 100)
	if err != nil {
		log.Error("Could not fetch from emptyTrashQueue queue", err)
	} else {
		for _, item := range items {
			t.emptyTrash(item, ente.Photos, repo.TrashEmptyQueue)
		}
	}

	itemsLocker, err2 := t.QueueRepo.GetItemsReadyForDeletion(repo.TrashEmptyLockerQueue, 100)
	if err2 != nil {
		log.Error("Could not fetch from emptyTrashLockerQueue queue", err2)
		return
	}
	for _, item := range itemsLocker {
		t.emptyTrash(item, ente.Locker, repo.TrashEmptyLockerQueue)
	}
}

func (t *TrashController) DeleteAgedTrashedFiles() {
	if t.deleteAgedTrashRunning {
		log.Info("Already deleting older trashed files, skipping cron")
		return
	}
	t.deleteAgedTrashRunning = true
	defer func() {
		t.deleteAgedTrashRunning = false
	}()

	lockName := "DeleteAgedTrashedFiles"
	lockStatus, err := t.TaskLockRepo.AcquireLock(lockName, time.MicrosecondsAfterHours(1), t.HostName)
	if err != nil || !lockStatus {
		log.Error("Unable to acquire lock to DeleteAgedTrashedFiles")
		return
	}
	defer func() {
		releaseErr := t.TaskLockRepo.ReleaseLock(lockName)
		if releaseErr != nil {
			log.WithError(releaseErr).Error("Error while releasing aged trash lock")
		}
	}()

	userIDToFileMap, err := t.TrashRepo.GetUserIDToFileIDsMapForDeletion()
	if err != nil {
		log.Error("Could not fetch trashed files for deletion", err)
		return
	}

	for userID, fileIDs := range userIDToFileMap {
		ctxLogger := log.WithFields(log.Fields{
			"user_id": userID,
			"fileIds": fileIDs,
		})
		ctxLogger.Info("start deleting old files from trash")
		err = t.TrashRepo.Delete(context.Background(), userID, fileIDs)
		if err != nil {
			ctxLogger.WithError(err).Error("failed to delete file from trash")
			continue
		}
		ctxLogger.Info("successfully deleted old files from trash")
	}
}

// trashedFiles must be sorted by increasing UpdatedAt.
func (t *TrashController) removeFilesWithVersion(trashedFiles []ente.Trash, version int64) []ente.Trash {
	var i = len(trashedFiles) - 1
	for ; i >= 0; i-- {
		if trashedFiles[i].UpdatedAt != version {
			break
		}
	}
	return trashedFiles[0 : i+1]
}

func (t *TrashController) trashCollection(item repo.QueueItem, queueName string, logger *log.Entry) {
	cID, _ := strconv.ParseInt(item.Item, 10, 64)
	collection, err := t.CollectionRepo.Get(cID)
	if err != nil {
		log.Error("Could not fetch collection "+item.Item, err)
		return
	}
	ctxLogger := logger.WithFields(log.Fields{
		"collection_id": cID,
		"user_id":       collection.Owner.ID,
		"queue":         queueName,
		"flow":          "trash_collection",
	})
	// File exclusivity spans collections, so lock the user rather than one
	// collection.
	lockName := fmt.Sprintf("CollectionTrash:%d", collection.Owner.ID)
	lockStatus, err := t.TaskLockRepo.AcquireLock(lockName, time.MicrosecondsAfterHours(1), t.HostName)
	if err != nil || !lockStatus {
		if err == nil {
			ctxLogger.Error("lock is already taken for deleting collection")
		} else {
			ctxLogger.WithError(err).Error("critical: error while acquiring lock")
		}
		return
	}
	defer func() {
		releaseErr := t.TaskLockRepo.ReleaseLock(lockName)
		if releaseErr != nil {
			ctxLogger.WithError(releaseErr).Error("Error while releasing lock")
		}
	}()
	ctxLogger.Info("start trashing collection")
	err = t.CollectionRepo.TrashV3(context.Background(), cID)
	if err != nil {
		ctxLogger.WithError(err).Error("failed to trash collection")
		return
	}
	err = t.QueueRepo.DeleteItem(queueName, item.Item)
	if err != nil {
		ctxLogger.WithError(err).Error("failed to delete item from queue")
		return
	}
}

func (t *TrashController) emptyTrash(item repo.QueueItem, app ente.App, queueName string) {
	lockName := fmt.Sprintf("EmptyTrash:%s", item.Item)
	lockStatus, err := t.TaskLockRepo.AcquireLock(lockName, time.MicrosecondsAfterHours(1), t.HostName)
	split := strings.Split(item.Item, repo.EmptyTrashQueueItemSeparator)
	userID, _ := strconv.ParseInt(split[0], 10, 64)
	lastUpdateAt, _ := strconv.ParseInt(split[1], 10, 64)
	ctxLogger := log.WithFields(log.Fields{
		"user_id":       userID,
		"lastUpdatedAt": lastUpdateAt,
		"flow":          "empty_trash",
		"app":           app,
	})

	if err != nil || !lockStatus {
		if err == nil {
			// todo: error only when lock is help for more than X durat
			ctxLogger.Error("lock is already taken for emptying trash")
		} else {
			ctxLogger.WithError(err).Error("critical: error while acquiring lock")
		}
		return
	}
	defer func() {
		releaseErr := t.TaskLockRepo.ReleaseLock(lockName)
		if releaseErr != nil {
			log.WithError(releaseErr).Error("Error while releasing lock")
		}
	}()

	ctxLogger.Info("Start emptying trash")
	fileIDs, err := t.TrashRepo.GetFilesIDsForDeletion(userID, lastUpdateAt, app)
	if err != nil {
		ctxLogger.WithError(err).Error("Failed to fetch fileIDs")
		return
	}
	ctx := context.Background()
	size := len(fileIDs)
	limit := repo.TrashBatchSize
	for lb := 0; lb < size; lb += limit {
		ub := min(lb+limit, size)
		batch := fileIDs[lb:ub]
		err = t.TrashRepo.Delete(ctx, userID, batch)
		if err != nil {
			ctxLogger.WithField("batchIDs", batch).WithError(err).Error("Failed while deleting batch")
			return
		}
	}
	err = t.QueueRepo.DeleteItem(queueName, item.Item)
	if err != nil {
		log.Error("Error while removing item from queue "+item.Item, err)
		return
	}
	ctxLogger.Info("Finished emptying trash")
}
