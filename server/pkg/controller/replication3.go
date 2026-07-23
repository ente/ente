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

// ReplicationController3 oversees version 3 of our object replication.
//
// The user's encrypted data starts off in 1 hot storage (Backblaze "b2"). This
// controller then takes over and replicates it the other two replicas. It keeps
// state in the object_copies table.
//
// Both v2 and v3 of object replication use the same hot storage (b2), but they
// replicate to different buckets thereafter.
//
// The current implementation only works if the hot storage is b2. This is not
// an inherent limitation, however the code has not yet been tested in other
// scenarios, so there is a safety check preventing the replication from
// happening if the current hot storage is not b2.
type ReplicationController3 struct {
	S3Config          *s3config.S3Config
	ObjectRepo        *repo.ObjectRepository
	ObjectCopiesRepo  *repo.ObjectCopiesRepository
	DiscordController *discord.DiscordController
	// URL of the Cloudflare worker to use for downloading the source object
	workerURL string
	// Base directory for temporary storage
	tempStorage string
	// Prometheus Metrics
	mUploadSuccess *prometheus.CounterVec
	mUploadFailure *prometheus.CounterVec
	// Cached S3 clients etc
	b2Client   *s3.S3
	b2Bucket   *string
	wasabiDest *UploadDestination
	scwDest    *UploadDestination
}

type UploadDestination struct {
	DC       string
	Client   *s3.S3
	Uploader *s3manager.Uploader
	Bucket   *string
	// The label to use for reporting metrics for uploads to this destination
	Label string
	// If true, we should ignore Wasabi 403 errors. See "Reuploads".
	HasComplianceHold bool
	// If true, the object is uploaded to the GLACIER class.
	IsGlacier bool
}

// StartReplication starts the background replication process.
//
// This method returns synchronously. ReplicationController3 will create
// suitable number of goroutines to parallelize and perform the replication
// asynchronously, as and when it notices new files that have not yet been
// replicated (it does this by querying the object_copies table).
func (c *ReplicationController3) StartReplication() error {
	// As a safety check, ensure that the current hot storage bucket is in b2.
	// This is because the replication v3 code has not yet been tested for other
	// scenarios (it'll likely work though, probably with minor modifications).
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
		// Stagger the workers
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
	// The s3manager.Uploader objects are safe for use concurrently. From the
	// AWS docs:
	//
	// > The Uploader structure that calls Upload(). It is safe to call Upload()
	//   on this structure for multiple objects and across concurrent goroutines.
	//   Mutating the Uploader's properties is not safe to be done concurrently.

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
		Uploader:          s3manager.NewUploaderWithClient(&wasabiClient),
		Bucket:            config.GetBucket(wasabiDC),
		Label:             "wasabi",
		HasComplianceHold: config.WasabiComplianceDC() == wasabiDC,
	}

	scwDC := config.GetColdScalewayDC()
	scwClient := config.GetS3Client(scwDC)
	c.scwDest = &UploadDestination{
		DC:       scwDC,
		Client:   &scwClient,
		Uploader: s3manager.NewUploaderWithClient(&scwClient),
		Bucket:   config.GetBucket(scwDC),
		Label:    "scaleway",
		// should be true, except when running in a local cluster (since minio doesn't
		// support specifying the GLACIER storage class).
		IsGlacier: !config.AreLocalBuckets(),
	}
}

// Entry point for the replication worker (goroutine)
//
// i is an arbitrary index of the current routine.
func (c *ReplicationController3) replicate(i int) {
	// This is just
	//
	//    while (true) { replicate() }
	//
	// but with an extra sleep for a bit if nothing got replicated - both when
	// something's wrong, or there's nothing to do.
	for {
		err := c.tryReplicate()
		if err != nil {
			// Sleep in proportion to the (arbitrary) index to space out the
			// workers further.
			time.Sleep(time.Duration(i+1) * time.Minute)
		}
	}
}

// Try to replicate an object.
//
// Return nil if something was replicated, otherwise return the error.
//
// A common and expected error is `sql.ErrNoRows`, which occurs if there are no
// objects left to replicate currently.
func (c *ReplicationController3) tryReplicate() error {
	// Fetch an object to replicate
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
		// Update the object_copies to mark this object as not requiring further
		// replication. The row in object_copies will get deleted when the next
		// scheduled object deletion runs.
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
		// We don't have free space right now, maybe because other big files are
		// being downloaded simultanously, but we might get space later, so mark
		// a failed attempt that'll get retried later.
		//
		// Log this error though, so that it gets noticed if it happens too
		// frequently (the instance might need a bigger disk).
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

// Download the object for objectKey from B2 hot storage, writing it into file.
//
// Return the size of the downloaded file.
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

// Get a presigned URL to download the object with objectKey from the B2 bucket.
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

// Upload, verify and then update the DB to mark replication to dest.
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
	// log if time taken is more than 2 seconds and speed is less than .5MB/s
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

	// The update of the object_keys is not done in the transaction where the
	// other updates to object_copies table are made. This is so that the
	// object_keys table (which is what'll be used to delete objects) is
	// (almost) always updated if the file gets uploaded successfully.
	//
	// The only time the update wouldn't happen is if museum gets restarted
	// between the successful completion of the upload to the bucket and this
	// query getting executed.
	//
	// While possible, that is a much smaller window as compared to the
	// transaction for updating object_copies, which could easily span minutes
	// as the transaction ends only after the object has been uploaded to all
	// replicas.
	rowsAffected, err := c.ObjectRepo.MarkObjectReplicated(in.ObjectKey, dest.DC)
	if err != nil {
		return failure(stacktrace.Propagate(err, "Failed to update object_keys to mark replication as completed"))
	}

	if rowsAffected != 1 {
		// It is possible that this row was updated earlier, after an upload
		// that got completed but before object_copies table could be updated in
		// the transaction (See "Reuploads").
		//
		// So do not treat this as an error.
		logger.Warnf("Expected 1 row to be updated, but got %d", rowsAffected)
	}

	err = dbUpdateCopies()
	if err != nil {
		return failure(stacktrace.Propagate(err, "Failed to update object_copies to mark replication as complete"))
	}

	c.mUploadSuccess.WithLabelValues(dest.Label).Inc()
	return nil
}

// Upload the given file to using uploader to the given bucket.
//
// # Reuploads
//
// It is possible that the object might already exist on remote. The known
// scenario where this might happen is if museum gets restarted after having
// completed the upload but before it got around to modifying the DB.
//
// The behaviour in this case is remote dependent.
//
//   - Uploading an object with the same key on Scaleway would work normally.
//
//   - But trying to add an object with the same key on the compliance locked
//     Wasabi would return an HTTP 403.
//
// We intercept the Wasabi 403 in this case and move ahead. The subsequent
// object verification using the HEAD request will act as a sanity check for
// the object.
func (c *ReplicationController3) uploadFile(in *UploadInput, dest *UploadDestination) error {
	// Rewind the file pointer back to the start for the next upload.
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

// Return true if the given error is because of an HTTP 403.
//
// See "Reuploads" for the scenario where these errors can arise.
//
// Specifically, this in an example of the HTTP 403 response we get when
// trying to add an object to a Wasabi bucket that already has a compliance
// locked object with the same key.
//
//		HTTP/1.1 403 Forbidden
//		Content-Type: application/xml
//		Date: Tue, 20 Dec 2022 10:23:33 GMT
//		Server: WasabiS3/7.10.1193-2022-11-23-84c72037e8 (head2)
//
//		<?xml version="1.0" encoding="UTF-8"?>
//		<Error>
//		 	<Code>AccessDenied</Code>
//		 	<Message>Access Denied</Message>
//		 	<RequestId>yyy</RequestId>
//		 	<HostId>zzz</HostId>
//	    </Error>
//
// Printing the error type and details produces this:
//
//	type: *s3err.RequestFailure
//	AccessDenied: Access Denied
//	  status code: 403, request id: yyy, host id: zzz
func (c *ReplicationController3) isRequestFailureAccessDenied(err error) bool {
	if reqerr, ok := err.(s3.RequestFailure); ok {
		if reqerr.Code() == "AccessDenied" {
			return true
		}
	}
	return false
}

// Verify the uploaded file by doing a HEAD check and comparing sizes
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
