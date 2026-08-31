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
	// TODO: object_cleanup: This code is only currently tested for B2
	if c.S3Config.GetHotDataCenter() != c.S3Config.GetHotBackblazeDC() {
		log.Info("Skipping RemovingUnreportedObjects since the Hot DC is not B2")
		return
	}

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

	count := 0

	tx, tempObjects, err := c.Repo.GetAndLockExpiredObjects()
	if err != nil {
		logger.Error(err)
		return count
	}
	defer tx.Rollback()

	for _, tempObject := range tempObjects {
		err = c.removeUnreportedObject(tx, tempObject)
		if err != nil {
			continue
		}
		count += 1
	}

	logger.Infof("Removed %d objects", count)

	// Always commit the batch. skip() delays failed rows to prevent a tight loop.
	cerr := tx.Commit()
	if cerr != nil {
		cerr = stacktrace.Propagate(cerr, "Failed to commit transaction")
		logger.Error(cerr)
	}

	return count
}

func (c *ObjectCleanupController) removeUnreportedObject(tx *sql.Tx, t ente.TempObject) error {
	// TODO: object_cleanup
	// This should use the DC from TempObject (once we start persisting it)
	dc := t.BucketId
	if dc == "" {
		dc = c.S3Config.GetHotDataCenter()
	}

	logger := log.WithFields(log.Fields{
		"task":        "remove-unreported-objects",
		"object_key":  t.ObjectKey,
		"data_center": dc,
		"upload_id":   t.UploadID,
	})

	skip := func(err error) error {
		logger.Errorf("Clearing tempObject failed: %v", err)
		newExpiry := time.MicrosecondsAfterDays(1)
		serr := c.Repo.SetExpiryForTempObject(tx, t, newExpiry)
		if serr != nil {
			logger.Errorf("Updating expiry for failed temp object failed: %v", serr)
		}
		return err
	}

	logger.Info("Clearing tempObject")

	exists, err := c.ObjectRepo.DoesObjectExist(tx, t.ObjectKey)
	if err != nil {
		return skip(stacktrace.Propagate(err, ""))
	}

	if exists {
		err := errors.New("aborting attempt to delete an object which has a DB entry")
		return skip(stacktrace.Propagate(err, ""))
	}

	if t.IsMultipart {
		err = c.abortMultipartUpload(t.ObjectKey, t.UploadID, dc)
		if err != nil {
			return skip(err)
		}
	}
	err = c.DeleteObjectFromDataCenter(t.ObjectKey, dc)
	if err != nil {
		return skip(err)
	}

	err = c.Repo.RemoveTempObject(tx, t)
	if err != nil {
		return skip(err)
	}

	return nil
}

func (c *ObjectCleanupController) AddTempObjectKey(objectKey string, dc string) error {
	expiry := time.Microseconds() + (2 * PreSignedRequestValidityDuration.Microseconds())
	return c.addCleanupEntryForObjectKey(objectKey, dc, expiry)
}

func (c *ObjectCleanupController) addCleanupEntryForObjectKey(objectKey string, dc string, expirationTime int64) error {
	err := c.Repo.AddTempObject(ente.TempObject{
		ObjectKey:   objectKey,
		IsMultipart: false,
		BucketId:    dc,
	}, expirationTime)
	return stacktrace.Propagate(err, "")
}

func (c *ObjectCleanupController) AddMultipartTempObjectKey(objectKey string, uploadID string, dc string) error {
	expiry := time.Microseconds() + (2 * PreSignedPartUploadRequestDuration.Microseconds())
	err := c.Repo.AddTempObject(ente.TempObject{
		ObjectKey:   objectKey,
		IsMultipart: true,
		UploadID:    uploadID,
		BucketId:    dc,
	}, expiry)
	return stacktrace.Propagate(err, "")
}

func (c *ObjectCleanupController) DeleteAllObjectsWithPrefix(prefix string, dc string) error {
	s3Client := c.S3Config.GetS3Client(dc)
	bucket := c.S3Config.GetBucket(dc)
	output, err := s3Client.ListObjectsV2(&s3.ListObjectsV2Input{
		Bucket: bucket,
		Prefix: &prefix,
	})
	if err != nil {
		log.WithFields(log.Fields{
			"prefix": prefix,
			"dc":     dc,
		}).WithError(err).Error("Failed to list objects")
		return stacktrace.Propagate(err, "")
	}
	var keys []string
	for _, obj := range output.Contents {
		keys = append(keys, *obj.Key)
	}
	for _, key := range keys {
		err = c.DeleteObjectFromDataCenter(key, dc)
		if err != nil {
			log.WithFields(log.Fields{
				"object_key": key,
				"dc":         dc,
			}).WithError(err).Error("Failed to delete object")
			return stacktrace.Propagate(err, "")
		}
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
