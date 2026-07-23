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

// ObjectCleanupController exposes functions to remove temporary object storage
// entries that were never committed to the database.
//
//  1. We create presigned URLs for clients to upload their objects to. It might
//     happen that the client is able to successfully upload to these URLs, but
//     not tell museum about the successful upload.
//
//  2. During replication, we might have half-done multipart uploads.
type ObjectCleanupController struct {
	Repo       *repo.ObjectCleanupRepository
	ObjectRepo *repo.ObjectRepository
	S3Config   *s3config.S3Config
}

// PreSignedRequestValidityDuration is the lifetime of a pre-signed URL
const PreSignedRequestValidityDuration = 7 * 24 * stime.Hour

// PreSignedPartUploadRequestDuration is the lifetime of a pre-signed multipart URL
const PreSignedPartUploadRequestDuration = 7 * 24 * stime.Hour

// Return a new instance of ObjectCleanupController
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

// StartRemovingUnreportedObjects starts goroutines to cleanup deletes those
// objects that were possibly uploaded but not reported to the database
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

// Entry point for the worker goroutine to cleanup unreported objects.
//
// i is an arbitrary index for the current goroutine.
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
		if !errors.Is(err, sql.ErrNoRows) {
			logger.Error(err)
		}
		return count
	}

	for _, tempObject := range tempObjects {
		err = c.removeUnreportedObject(tx, tempObject)
		if err != nil {
			continue
		}
		count += 1
	}

	logger.Infof("Removed %d objects", count)

	// We always commit the transaction, even on errors for individual rows. To
	// avoid object getting stuck in a loop, we increase their expiry times.

	cerr := tx.Commit()
	if cerr != nil {
		cerr = stacktrace.Propagate(err, "Failed to commit transaction")
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
	} else {
		err = c.DeleteObjectFromDataCenter(t.ObjectKey, dc)
	}
	if err != nil {
		return skip(err)
	}

	err = c.Repo.RemoveTempObject(tx, t)
	if err != nil {
		return skip(err)
	}

	return nil
}

// AddTempObjectKey creates a new temporary object entry.
//
// It persists a given object key as having been provided to a client for
// uploading. If a client does not successfully mark this object's upload as
// having completed within PreSignedRequestValidityDuration, this temp object
// will be cleaned up.
func (c *ObjectCleanupController) AddTempObjectKey(objectKey string, dc string) error {
	expiry := time.Microseconds() + (2 * PreSignedRequestValidityDuration.Microseconds())
	return c.addCleanupEntryForObjectKey(objectKey, dc, expiry)
}

// Add the object to a queue of "temporary" objects that are deleted (if they
// exist) if this entry is not removed from the queue by expirationTime.
func (c *ObjectCleanupController) addCleanupEntryForObjectKey(objectKey string, dc string, expirationTime int64) error {
	err := c.Repo.AddTempObject(ente.TempObject{
		ObjectKey:   objectKey,
		IsMultipart: false,
		BucketId:    dc,
	}, expirationTime)
	return stacktrace.Propagate(err, "")
}

// AddTempObjectMultipartKey creates a new temporary object entry for a
// multlipart upload.
//
// See AddTempObjectKey for more details.
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
			// This is expected now, since we just aborted the upload
			return nil
		}
		return stacktrace.Propagate(err, "")
	}
	if len(r.Parts) > 0 {
		return stacktrace.NewError("abort Failed")
	}
	return nil
}

// The original code here checked for NoSuchUpload, presumably because that is
// the error that B2 returns.
//
// Wasabi returns something similar:
//
//	<Error>
//	  <Code>NoSuchUpload</Code>
//	  <Message>The specified upload does not exist. The upload ID may be invalid,
//	           or the upload may have been aborted or completed.</Message>
//	...
//
// However, Scaleway returns a different error, NoSuchKey
//
//	<Error>
//	  <Code>NoSuchKey</Code>
//	  <Message>The specified key does not exist.</Message>
//	...
//
// This method returns true if either of these occur.
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
