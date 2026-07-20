package filedata

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/filedata"
	fileDataRepo "github.com/ente/museum/pkg/repo/filedata"
	enteTime "github.com/ente/museum/pkg/utils/time"

	log "github.com/sirupsen/logrus"
	"time"
)

// StartDataDeletion clears associated file data from the object store
func (c *Controller) StartDataDeletion() {
	go c.startDeleteWorkers(1)
}

func (c *Controller) startDeleteWorkers(n int) {
	log.Infof("Starting %d delete workers for fileData", n)

	for i := 0; i < n; i++ {
		go c.delete(i)
		// Stagger the workers
		time.Sleep(time.Duration(2*i+1) * time.Minute)
	}
}

// Entry point for the delete worker (goroutine)
//
// i is an arbitrary index of the current routine.
func (c *Controller) delete(i int) {
	// This is just
	//
	//    while (true) { delete() }
	//
	// but with an extra sleep for a bit if nothing got deleted - both when
	// something's wrong, or there's nothing to do.
	for {
		err := c.tryDelete()
		if err != nil {
			// Sleep in proportion to the (arbitrary) index to space out the
			// workers further.
			time.Sleep(time.Duration(i+5) * time.Minute)
		}
	}
}

func (c *Controller) tryDelete() error {
	newLockTime := enteTime.MicrosecondsAfterMinutes(10)
	row, err := c.Repo.GetPendingSyncDataAndExtendLock(context.Background(), newLockTime, true)
	if err != nil {
		if !errors.Is(err, sql.ErrNoRows) {
			log.Errorf("Could not fetch row for deletion: %s", err)
		}
		return err
	}
	if row.Type == ente.MlData {
		err = c.deleteFileRow(*row)
	} else if row.Type == ente.PreviewVideo {
		err = c.deleteFileRowV2(*row)
	} else {
		log.Warningf("Unsupported object type for deletion: %s", row.Type)
		return nil
	}
	if err != nil {
		log.Errorf("Could not delete file data: %s", err)
		return err
	}
	return nil
}

func (c *Controller) deleteFileRow(fileDataRow filedata.Row) error {
	if !fileDataRow.IsDeleted {
		return fmt.Errorf("file %d is not marked as deleted", fileDataRow.FileID)
	}
	fileID := fileDataRow.FileID
	ownerID, err := c.FileRepo.GetOwnerID(fileID)
	if err != nil {
		return err
	}
	if fileDataRow.UserID != ownerID {
		return c.reportDeletionInvariant(fileDataRow, fmt.Errorf(
			"file data owner mismatch for file %d: row user %d, file owner %d",
			fileID, fileDataRow.UserID, ownerID))
	}
	ctxLogger := log.WithField("file_id", fileDataRow.DeleteFromBuckets).WithField("type", fileDataRow.Type).WithField("user_id", fileDataRow.UserID)
	if fileDataRow.Type != ente.MlData {
		return c.reportDeletionInvariant(fileDataRow, fmt.Errorf(
			"unexpected file data type for deletion: got %s, want %s",
			fileDataRow.Type, ente.MlData))
	}
	objectKeys := filedata.AllObjects(fileID, ownerID, fileDataRow.Type)
	bucketColumnMap, err := getMapOfBucketItToColumn(fileDataRow)
	if err != nil {
		ctxLogger.WithError(err).Error("Failed to get bucketColumnMap")
		return err
	}
	// Delete objects and remove buckets
	for bucketID, columnName := range bucketColumnMap {
		for _, objectKey := range objectKeys {
			delErr := c.ObjectCleanupController.DeleteObjectFromDataCenter(objectKey, bucketID)
			if delErr != nil {
				ctxLogger.WithError(delErr).WithFields(log.Fields{
					"bucketID":  bucketID,
					"column":    columnName,
					"objectKey": objectKey,
				}).Error("Failed to delete object from datacenter")
				return delErr
			}
		}
		dbErr := c.Repo.RemoveBucket(fileDataRow, bucketID, columnName)
		if dbErr != nil {
			ctxLogger.WithError(dbErr).WithFields(log.Fields{
				"bucketID": bucketID,
				"column":   columnName,
			}).Error("Failed to remove bucket from db")
			return dbErr

		}
	}
	// Delete from Latest bucket
	for k := range objectKeys {
		err = c.ObjectCleanupController.DeleteObjectFromDataCenter(objectKeys[k], fileDataRow.LatestBucket)
		if err != nil {
			ctxLogger.WithError(err).Error("Failed to delete object from datacenter")
			return err
		}
	}
	if err := c.Repo.DeleteFileData(context.Background(), fileDataRow); err != nil {
		ctxLogger.WithError(err).Error("Failed to remove from db")
		return err
	}
	return nil
}

func (c *Controller) deleteFileRowV2(fileDataRow filedata.Row) error {
	if !fileDataRow.IsDeleted {
		return fmt.Errorf("file %d is not marked as deleted", fileDataRow.FileID)
	}
	fileID := fileDataRow.FileID
	ownerID, err := c.FileRepo.GetOwnerID(fileID)
	if err != nil {
		return err
	}
	if fileDataRow.UserID != ownerID {
		return c.reportDeletionInvariant(fileDataRow, fmt.Errorf(
			"file data owner mismatch for file %d: row user %d, file owner %d",
			fileID, fileDataRow.UserID, ownerID))
	}
	ctxLogger := log.WithField("file_id", fileDataRow.DeleteFromBuckets).WithField("type", fileDataRow.Type).WithField("user_id", fileDataRow.UserID)
	if fileDataRow.Type != ente.PreviewVideo {
		return c.reportDeletionInvariant(fileDataRow, fmt.Errorf(
			"unexpected file data type for deletion: got %s, want %s",
			fileDataRow.Type, ente.PreviewVideo))
	}
	delPrefix := filedata.DeletePrefix(fileID, ownerID, fileDataRow.Type)

	bucketColumnMap, err := getMapOfBucketItToColumn(fileDataRow)
	if err != nil {
		ctxLogger.WithError(err).Error("Failed to get bucketColumnMap")
		return err
	}
	// Delete objects and remove buckets
	for bucketID, columnName := range bucketColumnMap {
		delErr := c.ObjectCleanupController.DeleteAllObjectsWithPrefix(delPrefix, bucketID)
		if delErr != nil {
			ctxLogger.WithError(delErr).WithFields(log.Fields{
				"bucketID":  bucketID,
				"column":    columnName,
				"delPrefix": delPrefix,
			}).Error("Failed to deleteAllObjectsWithPrefix from datacenter")
			return delErr
		}

		dbErr := c.Repo.RemoveBucket(fileDataRow, bucketID, columnName)
		if dbErr != nil {
			ctxLogger.WithError(dbErr).WithFields(log.Fields{
				"bucketID": bucketID,
				"column":   columnName,
			}).Error("Failed to remove bucket from db")
			return dbErr

		}
	}
	// Delete from Latest bucket
	err = c.ObjectCleanupController.DeleteAllObjectsWithPrefix(delPrefix, fileDataRow.LatestBucket)
	if err != nil {
		ctxLogger.WithError(err).Error("Failed to delete object from datacenter")
		return err
	}

	if err := c.Repo.DeleteFileData(context.Background(), fileDataRow); err != nil {
		ctxLogger.WithError(err).Error("Failed to remove from db")
		return err
	}
	return nil
}

func getMapOfBucketItToColumn(row filedata.Row) (map[string]string, error) {
	bucketColumnMap := make(map[string]string)
	for _, bucketID := range row.DeleteFromBuckets {
		if existingColumn, exists := bucketColumnMap[bucketID]; exists {
			return nil, fmt.Errorf("duplicate DeleteFromBuckets ID found: %s in column %s", bucketID, existingColumn)
		}
		bucketColumnMap[bucketID] = fileDataRepo.DeletionColumn
	}
	for _, bucketID := range row.ReplicatedBuckets {
		if existingColumn, exists := bucketColumnMap[bucketID]; exists {
			return nil, fmt.Errorf("duplicate ReplicatedBuckets ID found: %s in column %s", bucketID, existingColumn)
		}
		bucketColumnMap[bucketID] = fileDataRepo.ReplicationColumn
	}
	for _, bucketID := range row.InflightReplicas {
		if existingColumn, exists := bucketColumnMap[bucketID]; exists {
			return nil, fmt.Errorf("duplicate InFlightBucketID found: %s in column %s", bucketID, existingColumn)
		}
		bucketColumnMap[bucketID] = fileDataRepo.InflightRepColumn
	}
	return bucketColumnMap, nil
}

func (c *Controller) reportDeletionInvariant(row filedata.Row, err error) error {
	log.WithFields(log.Fields{
		"file_id": row.FileID,
		"user_id": row.UserID,
		"type":    row.Type,
	}).WithError(err).Error("File data deletion invariant failed")
	c.DiscordController.Notify(fmt.Sprintf("%s: file data deletion invariant failed: %v", c.DiscordController.HostName, err))
	return err
}
