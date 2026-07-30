package controller

import (
	"context"
	"fmt"
	"sync"

	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/file"
	"github.com/ente/museum/pkg/utils/time"
	log "github.com/sirupsen/logrus"
)

const (
	OutdatedObjectQueueLock = "outdated_objects_queue_lock"
	outdatedObjectBatchSize = 200
)

func (c *FileController) CleanupOutdatedObjects() {
	log.Info("Cleaning up outdated objects")
	if c.outdatedCronRunning {
		log.Info("Skipping CleanupOutdatedObjects cron run as another instance is still running")
		return
	}
	c.outdatedCronRunning = true
	defer func() {
		c.outdatedCronRunning = false
	}()

	lockStatus := c.LockController.TryLock(OutdatedObjectQueueLock, time.MicrosecondsAfterHours(2))
	if !lockStatus {
		log.Warning(fmt.Sprintf("Failed to acquire lock %s", OutdatedObjectQueueLock))
		return
	}
	defer func() {
		c.LockController.ReleaseLock(OutdatedObjectQueueLock)
	}()

	ctx := context.Background()
	if c.outdatedQueueDisabled {
		log.Warn("Skipping outdatedObject queue preparation because it was disabled after a fully referenced batch")
	} else {
		c.prepareOutdatedObjectsForDeletion(ctx)
	}
	c.deleteReadyOutdatedObjects(ctx)
}

func (c *FileController) prepareOutdatedObjectsForDeletion(ctx context.Context) {
	items, err := c.QueueRepo.GetItemsReadyForDeletion(repo.OutdatedObjectsQueue, outdatedObjectBatchSize)
	if err != nil {
		log.WithError(err).Error("Failed to fetch outdated objects from queue")
		return
	}
	if len(items) == 0 {
		return
	}

	statuses, err := c.objectReferenceStatuses(ctx, items)
	if err != nil {
		log.WithError(err).Error("Failed to check outdated object references")
		return
	}
	itemsToProcess := make([]repo.QueueItem, 0, len(items))
	referenced := make([]repo.ObjectReferenceStatus, 0)
	for _, item := range items {
		status := statuses[item.Item]
		if status.InObjectKeys || status.InTempObjects {
			referenced = append(referenced, status)
			continue
		}
		itemsToProcess = append(itemsToProcess, item)
	}
	if len(referenced) > 0 && len(itemsToProcess) == 0 {
		status := referenced[0]
		log.WithField("item", status.ObjectKey).
			WithField("count", len(referenced)).
			WithField("in_object_keys", status.InObjectKeys).
			WithField("in_temp_objects", status.InTempObjects).
			Warn("Disabling outdatedObject queue preparation because fetched batch is fully referenced")
		c.outdatedQueueDisabled = true
		return
	}
	if len(referenced) > 0 {
		status := referenced[0]
		log.WithField("item", status.ObjectKey).
			WithField("count", len(referenced)).
			WithField("in_object_keys", status.InObjectKeys).
			WithField("in_temp_objects", status.InTempObjects).
			Warn("Skipping referenced outdatedObject queue item(s)")
	}

	var wg sync.WaitGroup
	itemChan := make(chan repo.QueueItem, len(itemsToProcess))

	for range 4 {
		wg.Go(func() {
			for item := range itemChan {
				func(item repo.QueueItem) {
					defer func() {
						if r := recover(); r != nil {
							log.WithField("item", item.Item).Errorf("Recovered from panic: %v", r)
						}
					}()
					c.prepareOutdatedObjectForDeletion(item)
				}(item)
			}
		})
	}
	for _, item := range itemsToProcess {
		itemChan <- item
	}
	close(itemChan)
	wg.Wait()
}

func (c *FileController) deleteReadyOutdatedObjects(ctx context.Context) {
	items, err := c.QueueRepo.GetItemsReadyForDeletion(repo.DeleteOutdatedObjectQueue, outdatedObjectBatchSize)
	if err != nil {
		log.WithError(err).Error("Failed to fetch outdated objects ready for deletion")
		return
	}
	if len(items) == 0 {
		return
	}

	var wg sync.WaitGroup
	itemChan := make(chan repo.QueueItem, len(items))

	for range 4 {
		wg.Go(func() {
			for item := range itemChan {
				func(item repo.QueueItem) {
					defer func() {
						if r := recover(); r != nil {
							log.WithField("item", item.Item).Errorf("Recovered from panic: %v", r)
						}
					}()
					c.deleteReadyOutdatedObject(item)
				}(item)
			}
		})
	}
	for _, item := range items {
		itemChan <- item
	}
	close(itemChan)
	wg.Wait()
}

func (c *FileController) prepareOutdatedObjectForDeletion(qItem repo.QueueItem) {
	lockName := file.GetLockNameForObject(qItem.Item)
	lockStatus, err := c.TaskLockingRepo.AcquireLock(lockName, time.MicrosecondsAfterHours(1), c.HostName)
	ctxLogger := log.WithField("item", qItem.Item).WithField("queue_id", qItem.Id)
	if err != nil || !lockStatus {
		ctxLogger.Warn("unable to acquire lock")
		return
	}
	defer func() {
		err = c.TaskLockingRepo.ReleaseLock(lockName)
		if err != nil {
			ctxLogger.Errorf("Error while releasing lock %s", err)
		}
	}()

	exists, err := c.ObjectRepo.DoesObjectOrTempObjectExist(qItem.Item)
	if err != nil {
		ctxLogger.WithError(err).Error("Failed to check object references")
		return
	}
	if exists {
		ctxLogger.Warn("Skipping outdated object cleanup because object key is still referenced")
		return
	}

	complianceDC := c.S3Config.WasabiComplianceDC()
	if complianceDC != "" {
		err = c.ObjectCleanupCtrl.disableConditionalHoldIfPresent(complianceDC, qItem.Item)
		if err != nil {
			ctxLogger.WithError(err).Error("Failed to disable object conditional hold")
			return
		}
	}

	tx, err := c.QueueRepo.DB.BeginTx(context.Background(), nil)
	if err != nil {
		ctxLogger.WithError(err).Error("Failed to begin transaction for delayed outdated object enqueue")
		return
	}
	err = c.QueueRepo.AddItems(context.Background(), tx, repo.DeleteOutdatedObjectQueue, []string{qItem.Item})
	if err != nil {
		tx.Rollback()
		ctxLogger.WithError(err).Error("Failed to enqueue outdated object for delayed deletion")
		return
	}
	err = tx.Commit()
	if err != nil {
		ctxLogger.WithError(err).Error("Failed to commit delayed outdated object enqueue")
		return
	}

	err = c.QueueRepo.DeleteItem(repo.OutdatedObjectsQueue, qItem.Item)
	if err != nil {
		ctxLogger.WithError(err).Error("Failed to remove outdated object item from the queue")
		return
	}
	ctxLogger.Info("Prepared outdated object for delayed deletion")
}

func (c *FileController) deleteReadyOutdatedObject(qItem repo.QueueItem) {
	lockName := file.GetLockNameForObject(qItem.Item)
	lockStatus, err := c.TaskLockingRepo.AcquireLock(lockName, time.MicrosecondsAfterHours(1), c.HostName)
	ctxLogger := log.WithField("item", qItem.Item).WithField("queue_id", qItem.Id)
	if err != nil || !lockStatus {
		ctxLogger.Warn("unable to acquire lock")
		return
	}
	defer func() {
		err = c.TaskLockingRepo.ReleaseLock(lockName)
		if err != nil {
			ctxLogger.Errorf("Error while releasing lock %s", err)
		}
	}()

	exists, err := c.ObjectRepo.DoesObjectOrTempObjectExist(qItem.Item)
	if err != nil {
		ctxLogger.WithError(err).Error("Failed to check object references")
		return
	}
	if exists {
		ctxLogger.Warn("Skipping outdated object deletion because object key is still referenced")
		return
	}

	dcs := c.outdatedObjectCleanupDataCenters()
	if len(dcs) == 0 {
		ctxLogger.Error("No active data centers found for outdated object cleanup")
		return
	}
	for _, dc := range dcs {
		err = c.ObjectCleanupCtrl.DeleteObjectFromDataCenter(qItem.Item, dc)
		if err != nil {
			ctxLogger.WithError(err).Error("Failed to delete outdated object from " + dc)
			return
		}
	}

	err = c.QueueRepo.DeleteItem(repo.DeleteOutdatedObjectQueue, qItem.Item)
	if err != nil {
		ctxLogger.WithError(err).Error("Failed to remove delayed outdated object item from the queue")
		return
	}
	ctxLogger.Info("Successfully cleaned outdated object")
}

func (c *FileController) outdatedObjectCleanupDataCenters() []string {
	candidates := []string{
		c.S3Config.GetHotBackblazeDC(),
		c.S3Config.GetHotWasabiDC(),
		c.S3Config.GetColdScalewayDC(),
		c.S3Config.GetHotDataCenter(),
		c.S3Config.GetSecondaryHotDataCenter(),
	}
	seen := make(map[string]bool)
	dcs := make([]string, 0, len(candidates))
	for _, dc := range candidates {
		if dc == "" || seen[dc] {
			continue
		}
		seen[dc] = true
		if !c.S3Config.IsBucketActive(dc) || !c.S3Config.ShouldDeleteFromDataCenter(dc) {
			continue
		}
		dcs = append(dcs, dc)
	}
	return dcs
}

func (c *FileController) objectReferenceStatuses(ctx context.Context, items []repo.QueueItem) (map[string]repo.ObjectReferenceStatus, error) {
	objectKeys := make([]string, 0, len(items))
	for _, item := range items {
		objectKeys = append(objectKeys, item.Item)
	}
	return c.ObjectRepo.GetObjectReferenceStatuses(ctx, objectKeys)
}
