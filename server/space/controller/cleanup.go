package controller

import (
	"context"
	"database/sql"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/s3"
	timeutil "github.com/ente/museum/pkg/utils/time"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/ente/stacktrace"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/viper"
)

const (
	spaceTempObjectCleanupBatchSize = 1000
	spaceTempObjectRetryDelay       = 24 * time.Hour
)

type CleanupController struct {
	AssetsRepo *spacerepo.AssetsRepository
}

func (c *CleanupController) StartRemovingUnreportedObjects() {
	workerCount := viper.GetInt("jobs.space-remove-unreported-objects.worker-count")
	if workerCount == 0 {
		workerCount = 1
	}

	log.Infof("Starting %d workers to space-remove-unreported-objects", workerCount)
	for i := 0; i < workerCount; i++ {
		go c.removeUnreportedObjectsWorker(i)
	}
}

func (c *CleanupController) removeUnreportedObjectsWorker(i int) {
	for {
		count := c.removeUnreportedObjects(context.Background())
		if count == 0 {
			time.Sleep(time.Duration(5+i) * time.Minute)
		} else {
			time.Sleep(time.Second)
		}
	}
}

func (c *CleanupController) removeUnreportedObjects(ctx context.Context) int {
	logger := log.WithField("task", "space-remove-unreported-objects")
	tx, tempObjects, err := c.AssetsRepo.GetAndLockExpiredTempObjects(ctx, timeutil.Microseconds(), spaceTempObjectCleanupBatchSize)
	if err != nil {
		logger.Error(err)
		return 0
	}

	var deleteAfterCommit []spacerepo.SpaceTempObjectRecord
	count := 0
	for _, tempObject := range tempObjects {
		action, err := c.prepareUnreportedObject(ctx, tx, tempObject)
		if err != nil {
			_ = tx.Rollback()
			logger.Error(err)
			return count
		}
		switch action {
		case tempObjectRemoved:
			count++
		case tempObjectDeleteAfterCommit:
			deleteAfterCommit = append(deleteAfterCommit, tempObject)
		}
	}
	if err := tx.Commit(); err != nil {
		logger.Error(stacktrace.Propagate(err, "failed to commit space temp object cleanup"))
		return count
	}
	for _, tempObject := range deleteAfterCommit {
		objectLogger := logger.WithFields(log.Fields{
			"object_key": tempObject.ObjectKey,
			"bucket_id":  tempObject.BucketID,
			"purpose":    tempObject.Purpose,
		})
		if err := c.deleteObject(tempObject); err != nil {
			objectLogger.Errorf("Deleting space temp object failed: %v", err)
			continue
		}
		if err := c.AssetsRepo.RemoveTempObject(ctx, tempObject.ObjectKey); err != nil {
			objectLogger.Errorf("Removing deleted space temp object failed: %v", err)
			continue
		}
		count++
	}
	if count > 0 {
		logger.Infof("Removed %d space temp objects", count)
	}
	return count
}

type tempObjectCleanupAction int

const (
	tempObjectRemoved tempObjectCleanupAction = iota + 1
	tempObjectDeleteAfterCommit
)

func (c *CleanupController) prepareUnreportedObject(ctx context.Context, tx *sql.Tx, tempObject spacerepo.SpaceTempObjectRecord) (tempObjectCleanupAction, error) {
	referenced, err := spacerepo.IsObjectReferencedTx(ctx, tx, tempObject.ObjectKey)
	if err != nil {
		return 0, stacktrace.Propagate(err, "failed to check space object reference")
	}
	if referenced {
		if err := spacerepo.RemoveTempObjectTx(ctx, tx, tempObject.ObjectKey); err != nil {
			return 0, err
		}
		return tempObjectRemoved, nil
	}
	retryAfter := timeutil.Microseconds() + int64(spaceTempObjectRetryDelay/time.Microsecond)
	if err := spacerepo.SetTempObjectCleanupAfterTx(ctx, tx, tempObject.ObjectKey, retryAfter); err != nil {
		return 0, err
	}
	return tempObjectDeleteAfterCommit, nil
}

func (c *CleanupController) deleteObject(tempObject spacerepo.SpaceTempObjectRecord) error {
	s3Client := c.AssetsRepo.S3Config.GetS3Client(tempObject.BucketID)
	_, err := s3Client.DeleteObject(&s3.DeleteObjectInput{
		Bucket: c.AssetsRepo.S3Config.GetBucket(tempObject.BucketID),
		Key:    aws.String(tempObject.ObjectKey),
	})
	return stacktrace.Propagate(err, "failed to delete space temp object from bucket %s", tempObject.BucketID)
}
