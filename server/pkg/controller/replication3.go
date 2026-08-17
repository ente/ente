package controller

import (
	"context"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/aws/aws-sdk-go/service/s3/s3manager"
	"github.com/ente/museum/pkg/controller/discord"
	"github.com/ente/museum/pkg/repo"
	fileutil "github.com/ente/museum/pkg/utils/file"
	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/ente/stacktrace"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/viper"
)

const (
	slowUploadThreshold             = 2 * time.Second
	slowSpeedThreshold              = 0.5 // MB/s
	replicationDelayForStaleObjects = 30
)

type ReplicationController3 struct {
	S3Config          *s3config.S3Config
	ObjectRepo        *repo.ObjectRepository
	ObjectCopiesRepo  *repo.ObjectCopiesRepository
	DiscordController *discord.DiscordController
	workerURL         string
	tempStorage       string
	mUploadSuccess    *prometheus.CounterVec
	mUploadFailure    *prometheus.CounterVec
	b2Client          *s3.S3
	b2Bucket          *string
	wasabiDest        *UploadDestination
	scwDest           *UploadDestination
}

type UploadDestination struct {
	DC                string
	Client            *s3.S3
	Uploader          *s3manager.Uploader
	Bucket            *string
	Label             string
	HasComplianceHold bool
	IsGlacier         bool
}

func (c *ReplicationController3) StartReplication() error {
	hotDC := c.S3Config.GetHotDataCenter()
	if hotDC != c.S3Config.GetHotBackblazeDC() {
		return fmt.Errorf("v3 replication can currently only run when the primary hot data center is Backblaze. Instead, it was %s", hotDC)
	}

	workerURL := viper.GetString("replication.worker-url")
	if workerURL == "" {
		log.Infof("replication.worker-url was not defined, files will downloaded directly during replication")
	} else {
		log.Infof("Worker URL to download objects for replication v3 is: %s", workerURL)
	}
	c.workerURL = workerURL

	c.createMetrics()
	err := c.createTemporaryStorage()
	if err != nil {
		return err
	}
	c.createDestinations()

	workerCount := viper.GetInt("replication.worker-count")
	if workerCount == 0 {
		workerCount = 6
	}

	go c.startWorkers(workerCount)

	return nil
}

func (c *ReplicationController3) startWorkers(n int) {
	log.Infof("Starting %d workers for replication v3", n)

	for i := 0; i < n; i++ {
		go c.replicate(i)
		time.Sleep(time.Duration(2*i+1) * time.Second)
	}
}

func (c *ReplicationController3) createMetrics() {
	c.mUploadSuccess = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "museum_replication_upload_success_total",
		Help: "Number of successful uploads during replication (each replica is counted separately)",
	}, []string{"destination"})
	c.mUploadFailure = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "museum_replication_upload_failure_total",
		Help: "Number of failed uploads during replication (each replica is counted separately)",
	}, []string{"destination"})
}

func (c *ReplicationController3) createTemporaryStorage() error {
	tempStorage := viper.GetString("replication.tmp-storage")
	if tempStorage == "" {
		tempStorage = "tmp/replication"
	}

	log.Infof("Temporary storage for replication v3 is: %s", tempStorage)

	err := fileutil.DeleteAllFilesInDirectory(tempStorage)
	if err != nil {
		return stacktrace.Propagate(err, "Failed to deleting old files from %s", tempStorage)
	}

	err = fileutil.MakeDirectoryIfNotExists(tempStorage)
	if err != nil {
		return stacktrace.Propagate(err, "Failed to create temporary storage %s", tempStorage)
	}

	c.tempStorage = tempStorage

	return nil
}

func (c *ReplicationController3) createDestinations() {
	// Scaleway limits multipart uploads to 1,000 parts.
	limitUploadParts := func(u *s3manager.Uploader) {
		u.MaxUploadParts = 1000
	}

	config := c.S3Config

	b2DC := config.GetHotBackblazeDC()
	b2Client := config.GetS3Client(b2DC)
	c.b2Client = &b2Client
	c.b2Bucket = config.GetBucket(b2DC)

	wasabiDC := config.GetHotWasabiDC()
	wasabiClient := config.GetS3Client(wasabiDC)
	c.wasabiDest = &UploadDestination{
		DC:                wasabiDC,
		Client:            &wasabiClient,
		Uploader:          s3manager.NewUploaderWithClient(&wasabiClient, limitUploadParts),
		Bucket:            config.GetBucket(wasabiDC),
		Label:             "wasabi",
		HasComplianceHold: config.WasabiComplianceDC() == wasabiDC,
	}

	scwDC := config.GetColdScalewayDC()
	scwClient := config.GetS3Client(scwDC)
	c.scwDest = &UploadDestination{
		DC:       scwDC,
		Client:   &scwClient,
		Uploader: s3manager.NewUploaderWithClient(&scwClient, limitUploadParts),
		Bucket:   config.GetBucket(scwDC),
		Label:    "scaleway",
		// MinIO does not support the GLACIER storage class.
		IsGlacier: !config.AreLocalBuckets(),
	}
}

func (c *ReplicationController3) replicate(i int) {
	for {
		err := c.tryReplicate()
		if err != nil {
			time.Sleep(time.Duration(i+1) * time.Minute)
		}
	}
}

func (c *ReplicationController3) tryReplicate() error {
	ctxWithTimeout, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	copies, err := c.ObjectCopiesRepo.GetAndLockUnreplicatedObject(ctxWithTimeout)
	if err != nil {
		if !errors.Is(err, sql.ErrNoRows) {
			log.Errorf("Could not fetch an object to replicate: %s", err)
		}
		return stacktrace.Propagate(err, "")
	}

	objectKey := copies.ObjectKey

	logger := log.WithFields(log.Fields{
		"task":       "replication",
		"object_key": objectKey,
	})

	done := func(err error) error {
		if err != nil {
			logger.Error(err)
			if strings.Contains(err.Error(), "size of the uploaded file") {
				delayErr := c.ObjectCopiesRepo.DelayNextAttemptByDays(context.Background(), objectKey, replicationDelayForStaleObjects)
				if delayErr != nil {
					logger.WithError(delayErr).Error("Failed to delay next attempt")
				}
			}
		}

		if err == nil {
			logger.Info("Replication attempt succeeded")
		} else {
			logger.WithError(err).Info("Replication attempt failed")
		}
		return err
	}

	logger.Info("Replication attempt start")

	if copies.B2 == nil {
		err := errors.New("expected B2 copy to be in place before we start replication")
		return done(stacktrace.Propagate(err, "Sanity check failed"))
	}

	if !copies.WantWasabi && !copies.WantSCW {
		err := errors.New("expected at least one of want_wasabi and want_scw to be true when trying to replicate")
		return done(stacktrace.Propagate(err, "Sanity check failed"))
	}

	ob, err := c.ObjectRepo.GetObjectState(objectKey)
	if err != nil {
		return done(stacktrace.Propagate(err, "Failed to fetch file's deleted status"))
	}

	if ob.IsFileDeleted || ob.IsUserDeleted {
		// Scheduled object deletion removes the object_copies row later.
		err = c.ObjectCopiesRepo.UnmarkFromReplication(objectKey)
		if err != nil {
			return done(stacktrace.Propagate(err, "Failed to mark an object not requiring further replication"))
		}
		logger.Infof("Skipping replication for deleted object (isFileDeleted = %v, isUserDeleted = %v)",
			ob.IsFileDeleted, ob.IsUserDeleted)
		return done(nil)
	}

	err = fileutil.EnsureSufficientSpace(ob.Size)
	if err != nil {
		return done(stacktrace.Propagate(err, ""))
	}

	filePath, file, err := fileutil.CreateTemporaryFile(c.tempStorage, objectKey)
	if err != nil {
		return done(stacktrace.Propagate(err, "Failed to create temporary file"))
	}
	defer os.Remove(filePath)
	defer file.Close()

	downloadedSize, err := c.downloadFromB2ViaWorker(objectKey, file, logger)
	if err != nil {
		return done(stacktrace.Propagate(err, "Failed to download object from B2"))
	}
	logger.Infof("Downloaded %d bytes to %s", downloadedSize, filePath)

	if downloadedSize != ob.Size {
		c.notifyDiscord(fmt.Sprintf("⚠️ Replication download size mismatch for %s: got %d bytes, expected %d", objectKey, downloadedSize, ob.Size))
		return done(stacktrace.NewError("downloaded size (%d) does not match expected size (%d)", downloadedSize, ob.Size))
	}

	in := &UploadInput{
		File:         file,
		ObjectKey:    objectKey,
		ExpectedSize: ob.Size,
		Logger:       logger,
	}

	err = nil

	if copies.WantWasabi && copies.Wasabi == nil {
		werr := c.replicateFile(in, c.wasabiDest, func() error {
			return c.ObjectCopiesRepo.MarkObjectReplicatedWasabi(objectKey)
		})
		err = werr
	}

	if copies.WantSCW && copies.SCW == nil {
		serr := c.replicateFile(in, c.scwDest, func() error {
			return c.ObjectCopiesRepo.MarkObjectReplicatedScaleway(objectKey)
		})
		if err == nil {
			err = serr
		}
	}
	return done(err)
}

func (c *ReplicationController3) downloadFromB2ViaWorker(objectKey string, file *os.File, logger *log.Entry) (int64, error) {
	presignedURL, err := c.getPresignedB2URL(objectKey)
	if err != nil {
		return 0, stacktrace.Propagate(err, "Could not create create presigned URL for downloading object")
	}

	presignedEncodedURL := base64.StdEncoding.EncodeToString([]byte(presignedURL))

	client := &http.Client{}

	request, err := http.NewRequest("GET", c.workerURL, nil)
	if err != nil {
		return 0, stacktrace.Propagate(err, "Could not create request for worker %s", c.workerURL)
	}

	q := request.URL.Query()
	q.Add("src", presignedEncodedURL)
	request.URL.RawQuery = q.Encode()

	if c.S3Config.AreLocalBuckets() || c.workerURL == "" {
		originalURL := request.URL
		request, err = http.NewRequest("GET", presignedURL, nil)
		if err != nil {
			return 0, stacktrace.Propagate(err, "Could not create request for URL %s", presignedURL)
		}
		logger.Infof("Bypassing workerURL %s and instead directly GETting %s", originalURL, presignedURL)
	}

	response, err := client.Do(request)
	if err != nil {
		return 0, stacktrace.Propagate(err, "Call to CF worker failed for object %s", objectKey)
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusOK {
		if response.StatusCode == http.StatusNotFound {
			c.notifyDiscord("🔥 Could not find object in HotStorage: " + objectKey)
		}
		err = fmt.Errorf("CF Worker GET for object %s failed with HTTP status %s", objectKey, response.Status)
		return 0, stacktrace.Propagate(err, "")
	}

	n, err := io.Copy(file, response.Body)
	if err != nil {
		return 0, stacktrace.Propagate(err, "Failed to write HTTP response to file")
	}

	return n, nil
}

func (c *ReplicationController3) getPresignedB2URL(objectKey string) (string, error) {
	r, _ := c.b2Client.GetObjectRequest(&s3.GetObjectInput{
		Bucket: c.b2Bucket,
		Key:    &objectKey,
	})
	return r.Presign(PreSignedRequestValidityDuration)
}

func (c *ReplicationController3) notifyDiscord(message string) {
	c.DiscordController.Notify(message)
}

type UploadInput struct {
	File         *os.File
	ObjectKey    string
	ExpectedSize int64
	Logger       *log.Entry
}

func (c *ReplicationController3) replicateFile(in *UploadInput, dest *UploadDestination, dbUpdateCopies func() error) error {
	start := time.Now()
	logger := in.Logger.WithFields(log.Fields{
		"destination": dest.Label,
		"bucket":      *dest.Bucket,
	})

	failure := func(err error) error {
		c.mUploadFailure.WithLabelValues(dest.Label).Inc()
		logger.Error(err)
		return err
	}

	err := c.uploadFile(in, dest)
	if err != nil {
		return failure(stacktrace.Propagate(err, "Failed to upload object"))
	}
	if time.Since(start) > slowUploadThreshold {
		elapsed := time.Since(start)
		uploadSpeedMBps := float64(in.ExpectedSize) / (elapsed.Seconds() * 1024 * 1024)

		if uploadSpeedMBps < slowSpeedThreshold {
			logger.WithFields(log.Fields{
				"sizeBytes":   in.ExpectedSize,
				"speedMBps":   uploadSpeedMBps,
				"elapsedSecs": elapsed.Seconds(),
				"label":       dest.Label,
			}).Infof("Slow replication upload to %s: %.2f seconds, speed: %.2f MB/s", dest.Label, elapsed.Seconds(), uploadSpeedMBps)
		}
	}

	err = c.verifyUploadedFileSize(in, dest)
	if err != nil {
		return failure(stacktrace.Propagate(err, "Failed to verify upload"))
	}

	// Record each successful upload in object_keys before updating object_copies.
	// The object_copies transaction can span all replica uploads; a restart in
	// that window must not leave an uploaded replica absent from deletion records.
	rowsAffected, err := c.ObjectRepo.MarkObjectReplicated(in.ObjectKey, dest.DC)
	if err != nil {
		return failure(stacktrace.Propagate(err, "Failed to update object_keys to mark replication as completed"))
	}

	if rowsAffected != 1 {
		// A previous interrupted attempt may already have recorded this replica.
		logger.Warnf("Expected 1 row to be updated, but got %d", rowsAffected)
	}

	err = dbUpdateCopies()
	if err != nil {
		return failure(stacktrace.Propagate(err, "Failed to update object_copies to mark replication as complete"))
	}

	c.mUploadSuccess.WithLabelValues(dest.Label).Inc()
	return nil
}

// A restart can leave an uploaded replica unrecorded in object_copies.
// Compliance-locked Wasabi returns 403 when that upload is retried, so allow
// the HEAD size check to verify the existing object.
func (c *ReplicationController3) uploadFile(in *UploadInput, dest *UploadDestination) error {
	in.File.Seek(0, io.SeekStart)

	up := s3manager.UploadInput{
		Bucket: dest.Bucket,
		Key:    &in.ObjectKey,
		Body:   in.File,
	}
	if dest.IsGlacier {
		up.StorageClass = aws.String(s3.ObjectStorageClassGlacier)
	}

	result, err := dest.Uploader.Upload(&up)
	if err != nil && dest.HasComplianceHold && c.isRequestFailureAccessDenied(err) {
		in.Logger.Infof("Ignoring object that already exists on remote (we'll verify it using a HEAD check): %s", err)
		return nil
	}
	if err != nil {
		return stacktrace.Propagate(err, "Upload to bucket %s failed", *dest.Bucket)
	}

	in.Logger.Infof("Uploaded to bucket %s: %s", *dest.Bucket, result.Location)

	return nil
}

func (c *ReplicationController3) isRequestFailureAccessDenied(err error) bool {
	if reqerr, ok := err.(s3.RequestFailure); ok {
		if reqerr.Code() == "AccessDenied" {
			return true
		}
	}
	return false
}

func (c *ReplicationController3) verifyUploadedFileSize(in *UploadInput, dest *UploadDestination) error {
	res, err := dest.Client.HeadObject(&s3.HeadObjectInput{
		Bucket: dest.Bucket,
		Key:    &in.ObjectKey,
	})
	if err != nil {
		return stacktrace.Propagate(err, "Fetching object info from bucket %s failed", *dest.Bucket)
	}

	if *res.ContentLength != in.ExpectedSize {
		err = fmt.Errorf("size of the uploaded file (%d) does not match the expected size (%d) in bucket %s for object %s",
			*res.ContentLength, in.ExpectedSize, *dest.Bucket, in.ObjectKey)
		c.notifyDiscord(fmt.Sprint(err))
		return stacktrace.Propagate(err, "")
	}

	return nil
}
