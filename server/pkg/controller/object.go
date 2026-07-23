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

// ObjectController manages various operations specific to object storage,
// including dealing with the special cases for individual replicas.
//
// The user's encrypted data is replicated to three places - 2 hot storage data
// centers, and 1 cold storage. All three of them provide S3 compatible APIs
// that we use to add and remove objects. However, there are still some specific
// (and intentional) differences in the way the three replicas work. e.g.
// objects stored in Wasabi are also placed under a special compliance mode,
// which is a Wasabi specific feature.
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

// RemoveComplianceHolds removes the Wasabi compliance hold from objects in
// Wasabi for files which have been deleted.
//
// Removing the compliance hold will allow these files to then be deleted when
// we subsequently attempt to delete the objects from Wasabi after
// DeleteObjectQueue delay (x days currently).
func (c *ObjectController) RemoveComplianceHolds() {
	if c.S3Config.WasabiComplianceDC() == "" {
		// Wasabi compliance is currently disabled in config, nothing to do.
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

// DisableObjectConditionalHold disables the Wasabi compliance conditional hold
// that has been placed on object. This way, we can enable these objects to be
// cleaned up when the user permanently deletes them.
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
