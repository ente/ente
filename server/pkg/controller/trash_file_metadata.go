package controller

import (
	"context"
	"fmt"
	"strconv"

	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/time"
	log "github.com/sirupsen/logrus"
)

func (t *TrashController) DropFileMetadataCron() {
	ctx := context.Background()
	lockName := "dropTrashedFileMetadata"
	logger := log.WithField("cron", lockName)
	if t.dropFileMetadataRunning {
		logger.Info("already running")
		return
	}
	t.dropFileMetadataRunning = true
	defer func() {
		t.dropFileMetadataRunning = false
	}()

	lockStatus, err := t.TaskLockRepo.AcquireLock(lockName, time.MicrosecondsAfterHours(1), t.HostName)
	if err != nil || !lockStatus {
		logger.Error("Unable to acquire lock")
		return
	}
	defer func() {
		releaseErr := t.TaskLockRepo.ReleaseLock(lockName)
		if releaseErr != nil {
			logger.WithError(releaseErr).Error("Error while releasing lock")
		}
	}()
	items, err := t.QueueRepo.GetItemsReadyForDeletion(repo.DropFileEncMetadataQueue, 10)
	if err != nil {
		logger.WithError(err).Error("getItemsReadyForDeletion failed")
		return
	}
	if len(items) == 0 {
		logger.Info("add entry for dropping fileMetadata")
		// insert entry with 0 as the last epochTime till when metadata is dropped.
		err = t.QueueRepo.InsertItem(context.Background(), repo.DropFileEncMetadataQueue, "0")
		if err != nil {
			logger.WithError(err).Error("failed to insert entry")
		}
		return
	}
	if len(items) > 1 {
		logger.Error(fmt.Sprintf("queue %s should not have more than one entry", repo.DropFileEncMetadataQueue))
	}
	qItem := items[0]
	droppedMetadataTill, parseErr := strconv.ParseInt(qItem.Item, 10, 64)
	if parseErr != nil {
		logger.WithError(parseErr).Error("failed to parse time")
		return
	}
	fileIDsWithUpdatedAt, err := t.TrashRepo.GetFileIdsForDroppingMetadata(droppedMetadataTill)
	if err != nil {
		logger.Error("error during next items fetch", err)
		return
	}
	if len(fileIDsWithUpdatedAt) == 0 {
		logger.Info("no pending entry")
		return
	}
	var maxUpdatedAt = int64(0)
	fileIDs := make([]int64, 0)
	for _, item := range fileIDsWithUpdatedAt {
		fileIDs = append(fileIDs, item.FileID)
		if item.UpdatedAt > maxUpdatedAt {
			maxUpdatedAt = item.UpdatedAt
		}
	}
	ctxLogger := logger.WithFields(log.Fields{
		"maxUpdatedAt": maxUpdatedAt,
		"fileIds":      fileIDs,
	})
	ctxLogger.Info("start dropping metadata")
	err = t.FileRepo.DropFilesMetadata(ctx, fileIDs)
	if err != nil {
		ctxLogger.WithError(err).Error("failed to scrub data")
		return
	}
	updateErr := t.QueueRepo.UpdateItem(ctx, repo.DropFileEncMetadataQueue, qItem.Id, strconv.FormatInt(maxUpdatedAt, 10))
	if updateErr != nil {
		ctxLogger.WithError(updateErr).Error("failed to update queueItem")
		return
	}
	ctxLogger.Info("successfully dropped metadata")
}
