package controller

import (
	"database/sql"
	"errors"
	"strings"
	stime "time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/ente/museum/pkg/external/wasabi"
	"github.com/ente/stacktrace"
	"github.com/spf13/viper"

	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/ente/museum/pkg/utils/time"
	log "github.com/sirupsen/logrus"
)

type ObjectCleanupController struct {
	Repo       *repo.ObjectCleanupRepository
	ObjectRepo *repo.ObjectRepository
	S3Config   *s3config.S3Config
}

const PreSignedRequestValidityDuration = 7 * 24 * stime.Hour

const PreSignedPartUploadRequestDuration = 7 * 24 * stime.Hour

func NewObjectCleanupController(
	objectCleanupRepo *repo.ObjectCleanupRepository,
	objectRepo *repo.ObjectRepository,
	s3Config *s3config.S3Config,
) *ObjectCleanupController {
	return &ObjectCleanupController{
		Repo:       objectCleanupRepo,
		ObjectRepo: objectRepo,
		S3Config:   s3Config,
	}
}

func (c *ObjectCleanupController) StartRemovingUnreportedObjects() {
	workerCount := viper.GetInt("jobs.remove-unreported-objects.worker-count")
	if workerCount == 0 {
		workerCount = 1
	}

	log.Infof("Starting %d workers to remove-unreported-objects", workerCount)

	for i := 0; i < workerCount; i++ {
		go c.removeUnreportedObjectsWorker(i)
	}
}

func (c *ObjectCleanupController) removeUnreportedObjectsWorker(i int) {
	for {
		count := c.removeUnreportedObjects()
		if count == 0 {
			stime.Sleep(stime.Duration(5+i) * stime.Minute)
		} else {
			stime.Sleep(stime.Second)
		}
	}
}

func (c *ObjectCleanupController) removeUnreportedObjects() int {
	logger := log.WithFields(log.Fields{
		"task": "remove-unreported-objects",
	})
	logger.Info("Removing unreported objects")

	tx, tempObjects, err := c.Repo.GetAndLockExpiredObjects()
	if err != nil {
		logger.Error(err)
		return 0
	}
	defer tx.Rollback()

	if len(tempObjects) == 0 {
		logger.Infof("Removed %d objects", 0)
		return 0
	}

	claimed, stagedCount, err := c.claimExpiredObjectsTx(tx, tempObjects)
	if err != nil {
		logger.Error(err)
		return 0
	}

	// Commit the DB claim/lease updates before any S3 I/O so we don't hold
	// pool connections or pin PostgreSQL's xmin horizon across S3 calls.
	if cerr := tx.Commit(); cerr != nil {
		cerr = stacktrace.Propagate(cerr, "Failed to commit transaction")
		logger.Error(cerr)
		return 0
	}

	count := stagedCount
	for _, t := range claimed {
		if err := c.processClaimedTempObject(t); err != nil {
			continue
		}
		count++
	}

	logger.Infof("Removed %d objects", count)
	return count
}

func (c *ObjectCleanupController) claimExpiredObjectsTx(tx *sql.Tx, tempObjects []ente.TempObject) ([]ente.TempObject, int, error) {
	objectKeys := make([]string, 0, len(tempObjects))
	for _, t := range tempObjects {
		objectKeys = append(objectKeys, t.ObjectKey)
	}
	existingKeys, err := c.ObjectRepo.GetExistingObjectKeysTx(tx, objectKeys)
	if err != nil {
		return nil, 0, stacktrace.Propagate(err, "")
	}

	now := time.Microseconds()
	retryExpiry := time.MicrosecondsAfterDays(1)
	complianceDC := c.S3Config.WasabiComplianceDC()

	var delayOnlyKeys []string
	var releaseHoldKeys []string
	var claimDeleteKeys []string
	claimed := make([]ente.TempObject, 0, len(tempObjects))
	stagedCount := 0

	for _, t := range tempObjects {
		dc := t.BucketId
		logger := log.WithFields(log.Fields{
			"task":        "remove-unreported-objects",
			"object_key":  t.ObjectKey,
			"data_center": dc,
			"upload_id":   t.UploadID,
		})
		logger.Info("Clearing tempObject")

		if dc == "" || !c.S3Config.IsBucketActive(dc) {
			logger.Errorf("Clearing tempObject failed: %v", stacktrace.NewError("temporary object bucket %q is not configured", dc))
			delayOnlyKeys = append(delayOnlyKeys, t.ObjectKey)
			continue
		}

		switch t.CleanupState {
		case ente.TempObjectUploading, ente.TempObjectReleaseHold, ente.TempObjectDelete:
		default:
			logger.Errorf("Clearing tempObject failed: %v", stacktrace.NewError("unknown temporary object cleanup state %q", t.CleanupState))
			delayOnlyKeys = append(delayOnlyKeys, t.ObjectKey)
			continue
		}

		if _, exists := existingKeys[t.ObjectKey]; exists {
			logger.Errorf("Clearing tempObject failed: %v", errors.New("aborting attempt to delete an object which has a DB entry"))
			delayOnlyKeys = append(delayOnlyKeys, t.ObjectKey)
			continue
		}

		switch t.CleanupState {
		case ente.TempObjectUploading:
			if dc == complianceDC {
				releaseHoldKeys = append(releaseHoldKeys, t.ObjectKey)
				stagedCount++
			} else {
				claimDeleteKeys = append(claimDeleteKeys, t.ObjectKey)
				t.CleanupState = ente.TempObjectDelete
				claimed = append(claimed, t)
			}
		case ente.TempObjectReleaseHold, ente.TempObjectDelete:
			delayOnlyKeys = append(delayOnlyKeys, t.ObjectKey)
			claimed = append(claimed, t)
		}
	}

	if err := c.Repo.SetExpiryForTempObjects(tx, delayOnlyKeys, retryExpiry); err != nil {
		return nil, 0, err
	}
	if err := c.Repo.SetCleanupStateForTempObjects(tx, releaseHoldKeys, ente.TempObjectReleaseHold, now); err != nil {
		return nil, 0, err
	}
	if err := c.Repo.SetCleanupStateForTempObjects(tx, claimDeleteKeys, ente.TempObjectDelete, retryExpiry); err != nil {
		return nil, 0, err
	}

	return claimed, stagedCount, nil
}

func (c *ObjectCleanupController) processClaimedTempObject(t ente.TempObject) error {
	dc := t.BucketId
	logger := log.WithFields(log.Fields{
		"task":        "remove-unreported-objects",
		"object_key":  t.ObjectKey,
		"data_center": dc,
		"upload_id":   t.UploadID,
	})

	if t.IsMultipart {
		if err := c.abortMultipartUpload(t.ObjectKey, t.UploadID, dc); err != nil {
			logger.Errorf("Clearing tempObject failed: %v", err)
			return err
		}
	}
	if t.CleanupState == ente.TempObjectReleaseHold {
		if err := c.disableConditionalHoldIfPresent(dc, t.ObjectKey); err != nil {
			logger.Errorf("Clearing tempObject failed: %v", err)
			return err
		}
		if err := c.Repo.CompleteHoldRelease(t.ObjectKey, time.MicrosecondsAfterDays(24)); err != nil {
			logger.Errorf("Clearing tempObject failed: %v", err)
			return err
		}
		return nil
	}
	if err := c.DeleteObjectFromDataCenter(t.ObjectKey, dc); err != nil {
		logger.Errorf("Clearing tempObject failed: %v", err)
		return err
	}
	if err := c.Repo.RemoveTempObject(t); err != nil {
		logger.Errorf("Clearing tempObject failed: %v", err)
		return err
	}
	return nil
}

func (c *ObjectCleanupController) AddTempObject(object ente.TempObject) error {
	validity := PreSignedRequestValidityDuration
	if object.IsMultipart {
		validity = PreSignedPartUploadRequestDuration
	}
	expiry := time.Microseconds() + 2*validity.Microseconds()
	err := c.Repo.AddTempObject(object, expiry)
	return stacktrace.Propagate(err, "")
}

func (c *ObjectCleanupController) DeleteAllObjectsWithPrefix(prefix string, dc string) error {
	s3Client := c.S3Config.GetS3Client(dc)
	bucket := c.S3Config.GetBucket(dc)
	var continuationToken *string
	for {
		output, err := s3Client.ListObjectsV2(&s3.ListObjectsV2Input{
			Bucket:            bucket,
			Prefix:            &prefix,
			ContinuationToken: continuationToken,
		})
		if err != nil {
			log.WithFields(log.Fields{
				"prefix": prefix,
				"dc":     dc,
			}).WithError(err).Error("Failed to list objects")
			return stacktrace.Propagate(err, "")
		}
		for _, obj := range output.Contents {
			err := c.DeleteObjectFromDataCenter(*obj.Key, dc)
			if err != nil {
				log.WithFields(log.Fields{
					"object_key": *obj.Key,
					"dc":         dc,
				}).WithError(err).Error("Failed to delete object")
				return stacktrace.Propagate(err, "")
			}
		}
		if !aws.BoolValue(output.IsTruncated) {
			break
		}
		nextContinuationToken := output.NextContinuationToken
		if aws.StringValue(nextContinuationToken) == "" ||
			aws.StringValue(nextContinuationToken) == aws.StringValue(continuationToken) {
			return errors.New("truncated object listing did not provide a new continuation token")
		}
		continuationToken = nextContinuationToken
	}
	return nil
}

func (c *ObjectCleanupController) DeleteObjectFromDataCenter(objectKey string, dc string) error {
	log.Info("Deleting " + objectKey + " from " + dc)
	var s3Client = c.S3Config.GetS3Client(dc)
	bucket := c.S3Config.GetBucket(dc)
	_, err := s3Client.DeleteObject(&s3.DeleteObjectInput{
		Bucket: bucket,
		Key:    &objectKey,
	})
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	err = s3Client.WaitUntilObjectNotExists(&s3.HeadObjectInput{
		Bucket: bucket,
		Key:    &objectKey,
	})
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}

func (c *ObjectCleanupController) disableConditionalHoldIfPresent(dc string, objectKey string) error {
	s3Client := c.S3Config.GetS3Client(dc)
	bucket := c.S3Config.GetBucket(dc)
	_, err := wasabi.PutObjectCompliance(&s3Client, &wasabi.PutObjectComplianceInput{
		Bucket: bucket,
		Key:    aws.String(objectKey),
		ObjectComplianceConfiguration: &wasabi.ObjectComplianceConfiguration{
			ConditionalHold: aws.Bool(false),
		},
	})
	if err != nil {
		// Missing objects do not need compliance-hold cleanup. Outdated objects may not
		// have reached Wasabi, or may already be gone there, while still needing cleanup
		// from the other active data centers.
		if strings.Contains(err.Error(), "NoSuchKey") || strings.Contains(err.Error(), "NotFound") {
			return nil
		}
		return stacktrace.Propagate(err, "Failed to update ObjectCompliance for %s/%s", *bucket, objectKey)
	}
	return nil
}

func (c *ObjectCleanupController) abortMultipartUpload(objectKey string, uploadID string, dc string) error {
	s3Client := c.S3Config.GetS3Client(dc)
	bucket := c.S3Config.GetBucket(dc)
	_, err := s3Client.AbortMultipartUpload(&s3.AbortMultipartUploadInput{
		Bucket:   bucket,
		Key:      &objectKey,
		UploadId: &uploadID,
	})
	if err != nil {
		if isUnknownUploadError(err) {
			log.Info("Could not find upload for " + objectKey)
			return nil
		}
		return stacktrace.Propagate(err, "")
	}
	r, err := s3Client.ListParts(&s3.ListPartsInput{
		Bucket:   bucket,
		Key:      &objectKey,
		UploadId: &uploadID,
	})
	if err != nil {
		if isUnknownUploadError(err) {
			return nil
		}
		return stacktrace.Propagate(err, "")
	}
	if len(r.Parts) > 0 {
		return stacktrace.NewError("abort Failed")
	}
	return nil
}

func isUnknownUploadError(err error) bool {
	// B2, Wasabi
	if strings.Contains(err.Error(), "NoSuchUpload") {
		return true
	}
	// Scaleway
	if strings.Contains(err.Error(), "NoSuchKey") {
		return true
	}
	return false
}
