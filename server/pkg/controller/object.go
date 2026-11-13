package controller

import (
	"fmt"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/ente/museum/pkg/controller/lock"
	"github.com/ente/museum/pkg/external/wasabi"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/file"
	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	log "github.com/sirupsen/logrus"
)

type ObjectController struct {
	S3Config              *s3config.S3Config
	ObjectRepo            *repo.ObjectRepository
	QueueRepo             *repo.QueueRepository
	LockController        *lock.LockController
	complianceCronRunning bool
}

const (
	RemoveComplianceHoldsLock = "remove_compliance_holds_lock"
)

// Wasabi objects cannot be deleted until their compliance hold is removed.
func (c *ObjectController) RemoveComplianceHolds() {
	if c.S3Config.WasabiComplianceDC() == "" {
		return
	}
	if c.complianceCronRunning {
		log.Info("Skipping RemoveComplianceHolds cron run as another instance is still running")
		return
	}
	c.complianceCronRunning = true
	defer func() {
		c.complianceCronRunning = false
	}()

	lockStatus := c.LockController.TryLock(RemoveComplianceHoldsLock, time.MicrosecondsAfterHours(2))
	if !lockStatus {
		log.Warning(fmt.Sprintf("Failed to acquire lock %s", RemoveComplianceHoldsLock))
		return
	}
	defer func() {
		c.LockController.ReleaseLock(RemoveComplianceHoldsLock)
	}()

	items, err := c.QueueRepo.GetItemsReadyForDeletion(repo.RemoveComplianceHoldQueue, 1500)
	if err != nil {
		log.WithError(err).Error("Failed to fetch items from queue")
		return
	}

	log.Infof("Removing compliance holds on %d deleted files", len(items))
	for _, i := range items {
		c.removeComplianceHold(i)
	}

	log.Infof("Removed compliance holds on %d deleted files", len(items))
}

func (c *ObjectController) removeComplianceHold(qItem repo.QueueItem) {
	logger := log.WithFields(log.Fields{
		"item":     qItem.Item,
		"queue_id": qItem.Id,
	})

	objectKey := qItem.Item

	lockName := file.GetLockNameForObject(objectKey)
	if !c.LockController.TryLock(lockName, time.MicrosecondsAfterHours(1)) {
		logger.Info("Unable to acquire lock")
		return
	}
	defer c.LockController.ReleaseLock(lockName)

	dcs, err := c.ObjectRepo.GetDataCentersForObject(objectKey)
	if err != nil {
		logger.Error("Could not fetch datacenters", err)
		return
	}

	config := c.S3Config
	complianceDC := config.WasabiComplianceDC()
	s3Client := config.GetS3Client(complianceDC)
	bucket := *config.GetBucket(complianceDC)

	for _, dc := range dcs {
		if dc == complianceDC {
			logger.Info("Removing compliance hold")
			err = c.DisableObjectConditionalHold(&s3Client, bucket, objectKey)
			if err != nil {
				logger.WithError(err).Errorf("Failed to remove compliance hold (dc: %s, bucket: %s)", dc, bucket)
				return
			}
			logger.Infof("Removed compliance hold for %s/%s", bucket, objectKey)
			break
		}
	}

	err = c.QueueRepo.DeleteItem(repo.RemoveComplianceHoldQueue, qItem.Item)
	if err != nil {
		logger.WithError(err).Error("Failed to remove item from the queue")
		return
	}
}

func (c *ObjectController) DisableObjectConditionalHold(s3Client *s3.S3, bucket string, objectKey string) error {
	_, err := wasabi.PutObjectCompliance(s3Client, &wasabi.PutObjectComplianceInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(objectKey),
		ObjectComplianceConfiguration: &wasabi.ObjectComplianceConfiguration{
			ConditionalHold: aws.Bool(false),
		},
	})
	return stacktrace.Propagate(err, "Failed to update ObjectCompliance for %s/%s", bucket, objectKey)
}
