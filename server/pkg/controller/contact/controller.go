package contact

import (
	"context"
	"errors"
	"io"
	"os"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/aws/aws-sdk-go/service/s3/s3manager"
	"github.com/ente/museum/ente"
	contactmodel "github.com/ente/museum/ente/contact"
	basecontroller "github.com/ente/museum/pkg/controller"
	contactrepo "github.com/ente/museum/pkg/repo/contact"
	"github.com/ente/museum/pkg/utils/auth"
	fileutil "github.com/ente/museum/pkg/utils/file"
	"github.com/ente/museum/pkg/utils/s3config"
	enteTime "github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/viper"
)

type Controller struct {
	Repo                    *contactrepo.Repository
	ObjectCleanupController *basecontroller.ObjectCleanupController
	S3Config                *s3config.S3Config
	downloadManagerCache    map[string]*s3manager.Downloader
	tempStorage             string
	replicateAttachmentFn   func(context.Context, contactmodel.Attachment, string) error
	deleteAttachmentFn      func(contactmodel.Attachment, string) error
	verifyAttachmentFn      func(string, string, int64) error
}

func New(
	repo *contactrepo.Repository,
	objectCleanupController *basecontroller.ObjectCleanupController,
	s3Config *s3config.S3Config,
) *Controller {
	attachmentDcs := []string{
		s3Config.GetHotBackblazeDC(),
		s3Config.GetHotWasabiDC(),
		s3Config.GetWasabiDerivedDC(),
		s3Config.GetDerivedStorageDataCenter(),
		"scw-eu-fr",
		"scw-eu-fr-v3",
		"b5",
		"b6",
	}
	cache := make(map[string]*s3manager.Downloader, len(attachmentDcs))
	for _, dc := range attachmentDcs {
		s3Client := s3Config.GetS3Client(dc)
		cache[dc] = s3manager.NewDownloaderWithClient(&s3Client)
	}
	ctrl := &Controller{
		Repo:                    repo,
		ObjectCleanupController: objectCleanupController,
		S3Config:                s3Config,
		downloadManagerCache:    cache,
	}
	ctrl.replicateAttachmentFn = ctrl.replicateAttachmentObject
	ctrl.deleteAttachmentFn = ctrl.deleteAttachmentObject
	ctrl.verifyAttachmentFn = ctrl.verifyAttachmentSize
	return ctrl
}

func (c *Controller) Create(ctx *gin.Context, req contactmodel.CreateRequest) (*contactmodel.Entity, error) {
	if err := req.Validate(); err != nil {
		return nil, stacktrace.Propagate(err, "invalid create contact request")
	}
	exists, err := c.Repo.ContactUserExists(ctx, req.ContactUserID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to validate contact user")
	}
	if !exists {
		return nil, stacktrace.Propagate(
			ente.NewBadRequestWithMessage("contactUserID does not exist"),
			"",
		)
	}
	userID := auth.GetUserID(ctx.Request.Header)
	canCreate, err := c.Repo.CanCreateContact(ctx, userID, req.ContactUserID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to validate contact eligibility")
	}
	if !canCreate {
		return nil, stacktrace.Propagate(
			ente.NewBadRequestWithMessage("contactUserID is not eligible to be added as a contact"),
			"",
		)
	}
	id, err := c.Repo.Create(ctx, userID, req)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return c.Repo.Get(ctx, userID, id)
}

func (c *Controller) Get(ctx *gin.Context, contactID string) (*contactmodel.Entity, error) {
	if !contactmodel.IsValidContactID(contactID) {
		return nil, ente.NewBadRequestWithMessage("invalid contact id")
	}
	userID := auth.GetUserID(ctx.Request.Header)
	return c.Repo.Get(ctx, userID, contactID)
}

func (c *Controller) GetDiff(ctx *gin.Context, req contactmodel.DiffRequest) ([]contactmodel.Entity, error) {
	if req.Limit <= 0 || req.Limit > 5000 {
		return nil, ente.NewBadRequestWithMessage("limit must be between 1 and 5000")
	}
	userID := auth.GetUserID(ctx.Request.Header)
	return c.Repo.GetDiff(ctx, userID, *req.SinceTime, req.Limit)
}

func (c *Controller) Update(ctx *gin.Context, contactID string, req contactmodel.UpdateRequest) (*contactmodel.Entity, error) {
	if !contactmodel.IsValidContactID(contactID) {
		return nil, ente.NewBadRequestWithMessage("invalid contact id")
	}
	if err := req.Validate(); err != nil {
		return nil, stacktrace.Propagate(err, "invalid update contact request")
	}
	userID := auth.GetUserID(ctx.Request.Header)
	exists, err := c.Repo.ContactUserExists(ctx, req.ContactUserID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to validate contact user")
	}
	if !exists {
		return nil, stacktrace.Propagate(
			ente.NewBadRequestWithMessage("contactUserID does not exist"),
			"",
		)
	}
	updateState, err := c.Repo.GetContactUpdateState(ctx, userID, contactID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to fetch contact")
	}
	if updateState.IsDeleted || updateState.ContactUserID != req.ContactUserID {
		canUpdate, err := c.Repo.CanCreateContact(ctx, userID, req.ContactUserID)
		if err != nil {
			return nil, stacktrace.Propagate(err, "failed to validate contact eligibility")
		}
		if !canUpdate {
			return nil, stacktrace.Propagate(
				ente.NewBadRequestWithMessage("contactUserID is not eligible to be added as a contact"),
				"",
			)
		}
	}
	if err := c.Repo.Update(ctx, userID, contactID, req); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return c.Repo.Get(ctx, userID, contactID)
}

func (c *Controller) Delete(ctx *gin.Context, contactID string) error {
	if !contactmodel.IsValidContactID(contactID) {
		return ente.NewBadRequestWithMessage("invalid contact id")
	}
	userID := auth.GetUserID(ctx.Request.Header)
	return c.Repo.Delete(ctx, userID, contactID)
}

func (c *Controller) GetAttachmentUploadURL(ctx *gin.Context, attachmentTypeRaw string, req contactmodel.AttachmentUploadURLRequest) (*contactmodel.AttachmentUploadURL, error) {
	attachmentType, policy, err := c.attachmentTypeAndPolicy(attachmentTypeRaw)
	if err != nil {
		return nil, stacktrace.Propagate(err, "invalid attachment type")
	}
	if err := req.Validate(policy); err != nil {
		return nil, stacktrace.Propagate(err, "invalid attachment upload-url request")
	}

	userID := auth.GetUserID(ctx.Request.Header)
	attachmentID := contactmodel.NewAttachmentID()
	objectKey := contactmodel.AttachmentObjectKey(userID, attachmentType, attachmentID)
	dc := c.S3Config.GetAttachmentBucketID(string(attachmentType))

	s3Client := c.S3Config.GetS3Client(dc)
	putReq, _ := s3Client.PutObjectRequest(&s3.PutObjectInput{
		Bucket:        c.S3Config.GetBucket(dc),
		Key:           aws.String(objectKey),
		ContentLength: aws.Int64(req.ContentLength),
		ContentMD5:    aws.String(req.ContentMD5),
	})
	url, err := putReq.Presign(basecontroller.PreSignedRequestValidityDuration)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to presign profile picture upload url")
	}
	if err := c.ObjectCleanupController.AddTempObjectKey(objectKey, dc); err != nil {
		return nil, stacktrace.Propagate(err, "failed to stage temp object for attachment upload")
	}

	return &contactmodel.AttachmentUploadURL{
		AttachmentID: attachmentID,
		URL:          url,
	}, nil
}

func (c *Controller) GetProfilePictureUploadURL(ctx *gin.Context, req contactmodel.AttachmentUploadURLRequest) (*contactmodel.AttachmentUploadURL, error) {
	return c.GetAttachmentUploadURL(ctx, string(contactmodel.ProfilePicture), req)
}

func (c *Controller) AttachContactAttachment(ctx *gin.Context, contactID string, attachmentTypeRaw string, req contactmodel.CommitAttachmentRequest) (*contactmodel.Entity, error) {
	if !contactmodel.IsValidContactID(contactID) {
		return nil, ente.NewBadRequestWithMessage("invalid contact id")
	}
	attachmentType, policy, err := c.attachmentTypeAndPolicy(attachmentTypeRaw)
	if err != nil {
		return nil, stacktrace.Propagate(err, "invalid attachment type")
	}
	if err := req.Validate(policy); err != nil {
		return nil, stacktrace.Propagate(err, "invalid attach attachment request")
	}
	userID := auth.GetUserID(ctx.Request.Header)
	stagedBucketID, err := c.Repo.GetStagedAttachmentBucket(ctx, userID, attachmentType, req.AttachmentID)
	if err != nil {
		if errors.Is(err, &ente.ErrNotFoundError) {
			return nil, stacktrace.Propagate(
				ente.NewBadRequestWithMessage("staged attachment upload not found"),
				"",
			)
		}
		return nil, stacktrace.Propagate(err, "failed to look up staged attachment")
	}
	objectKey := contactmodel.AttachmentObjectKey(userID, attachmentType, req.AttachmentID)
	if err := c.verifyAttachmentFn(stagedBucketID, objectKey, req.Size); err != nil {
		return nil, stacktrace.Propagate(err, "staged attachment verification failed")
	}
	return c.Repo.AttachContactAttachment(ctx, userID, contactID, attachmentType, req.AttachmentID, req.Size)
}

func (c *Controller) AttachProfilePicture(ctx *gin.Context, contactID string, req contactmodel.CommitAttachmentRequest) (*contactmodel.Entity, error) {
	return c.AttachContactAttachment(ctx, contactID, string(contactmodel.ProfilePicture), req)
}

func (c *Controller) GetAttachmentURL(ctx *gin.Context, attachmentTypeRaw string, attachmentID string) (*contactmodel.SignedURLResponse, error) {
	attachmentType, _, err := c.attachmentTypeAndPolicy(attachmentTypeRaw)
	if err != nil {
		return nil, stacktrace.Propagate(err, "invalid attachment type")
	}
	if !contactmodel.IsValidAttachmentID(attachmentID) {
		return nil, ente.NewBadRequestWithMessage("invalid attachment id")
	}
	userID := auth.GetUserID(ctx.Request.Header)
	attachment, err := c.Repo.GetAttachment(ctx, userID, attachmentID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if attachment.IsDeleted || attachment.AttachmentType != attachmentType {
		return nil, &ente.ErrNotFoundError
	}
	objectKey := contactmodel.AttachmentObjectKey(userID, attachment.AttachmentType, attachment.AttachmentID)
	s3Client := c.S3Config.GetS3Client(attachment.LatestBucket)
	input := &s3.GetObjectInput{
		Bucket:                     c.S3Config.GetBucket(attachment.LatestBucket),
		Key:                        aws.String(objectKey),
		ResponseContentDisposition: aws.String("attachment"),
	}
	getReq, _ := s3Client.GetObjectRequest(input)
	url, err := getReq.Presign(basecontroller.PreSignedRequestValidityDuration)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to presign profile picture download url")
	}
	return &contactmodel.SignedURLResponse{URL: url}, nil
}

func (c *Controller) GetCurrentContactAttachmentURL(ctx *gin.Context, contactID string, attachmentTypeRaw string) (*contactmodel.SignedURLResponse, error) {
	if !contactmodel.IsValidContactID(contactID) {
		return nil, ente.NewBadRequestWithMessage("invalid contact id")
	}
	attachmentType, _, err := c.attachmentTypeAndPolicy(attachmentTypeRaw)
	if err != nil {
		return nil, stacktrace.Propagate(err, "invalid attachment type")
	}
	userID := auth.GetUserID(ctx.Request.Header)
	entity, err := c.Repo.Get(ctx, userID, contactID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if entity.IsDeleted {
		return nil, &ente.ErrNotFoundError
	}
	attachmentID := c.currentAttachmentID(entity, attachmentType)
	if attachmentID == nil {
		return nil, &ente.ErrNotFoundError
	}
	return c.GetAttachmentURL(ctx, attachmentTypeRaw, *attachmentID)
}

func (c *Controller) GetProfilePictureURL(ctx *gin.Context, contactID string) (*contactmodel.SignedURLResponse, error) {
	return c.GetCurrentContactAttachmentURL(ctx, contactID, string(contactmodel.ProfilePicture))
}

func (c *Controller) DeleteContactAttachment(ctx *gin.Context, contactID string, attachmentTypeRaw string) (*contactmodel.Entity, error) {
	if !contactmodel.IsValidContactID(contactID) {
		return nil, ente.NewBadRequestWithMessage("invalid contact id")
	}
	attachmentType, _, err := c.attachmentTypeAndPolicy(attachmentTypeRaw)
	if err != nil {
		return nil, stacktrace.Propagate(err, "invalid attachment type")
	}
	userID := auth.GetUserID(ctx.Request.Header)
	return c.Repo.DeleteContactAttachment(ctx, userID, contactID, attachmentType)
}

func (c *Controller) DeleteProfilePicture(ctx *gin.Context, contactID string) (*contactmodel.Entity, error) {
	return c.DeleteContactAttachment(ctx, contactID, string(contactmodel.ProfilePicture))
}

func (c *Controller) attachmentTypeAndPolicy(raw string) (contactmodel.AttachmentType, contactmodel.AttachmentPolicy, error) {
	attachmentType, err := contactmodel.ParseAttachmentType(raw)
	if err != nil {
		return "", contactmodel.AttachmentPolicy{}, err
	}
	policy, err := attachmentType.Policy()
	if err != nil {
		return "", contactmodel.AttachmentPolicy{}, err
	}
	return attachmentType, policy, nil
}

func (c *Controller) currentAttachmentID(entity *contactmodel.Entity, attachmentType contactmodel.AttachmentType) *string {
	switch attachmentType {
	case contactmodel.ProfilePicture:
		return entity.ProfilePictureAttachmentID
	default:
		return nil
	}
}

func (c *Controller) StartReplication() error {
	workerCount := viper.GetInt("replication.contact-attachments.worker-count")
	if workerCount == 0 {
		workerCount = 2
	}
	if err := c.createTemporaryStorage(); err != nil {
		return stacktrace.Propagate(err, "failed to create temporary storage")
	}
	go c.startReplicationWorkers(workerCount)
	return nil
}

func (c *Controller) StartDataDeletion() {
	go c.startDeleteWorkers(1)
}

func (c *Controller) createTemporaryStorage() error {
	tempStorage := viper.GetString("replication.contact-attachments.tmp-storage")
	if tempStorage == "" {
		tempStorage = "tmp/replication-contact-attachments"
	}
	if err := fileutil.DeleteAllFilesInDirectory(tempStorage); err != nil {
		return stacktrace.Propagate(err, "failed deleting old files from %s", tempStorage)
	}
	if err := fileutil.MakeDirectoryIfNotExists(tempStorage); err != nil {
		return stacktrace.Propagate(err, "failed to create temporary storage %s", tempStorage)
	}
	c.tempStorage = tempStorage
	return nil
}

func (c *Controller) startReplicationWorkers(n int) {
	log.Infof("Starting %d workers for contact attachment replication", n)
	for i := 0; i < n; i++ {
		go c.replicate(i)
		time.Sleep(time.Duration(2*i+1) * time.Second)
	}
}

func (c *Controller) replicate(i int) {
	for {
		if err := c.tryReplicate(); err != nil {
			time.Sleep(time.Duration(i+1) * time.Minute)
		}
	}
}

func (c *Controller) tryReplicate() error {
	newLockTime := enteTime.MicrosecondsAfterMinutes(240)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Minute)
	defer cancel()

	row, err := c.Repo.GetPendingSyncAttachmentAndExtendLock(ctx, newLockTime, false)
	if err != nil {
		return err
	}
	if err := c.replicateAttachmentRow(ctx, *row); err != nil {
		return err
	}
	return c.Repo.ResetAttachmentSyncLock(ctx, *row, newLockTime)
}

func (c *Controller) replicateAttachmentRow(ctx context.Context, row contactmodel.Attachment) error {
	wantInBucketIDs := map[string]bool{}
	wantInBucketIDs[c.S3Config.GetAttachmentBucketID(string(row.AttachmentType))] = true
	for _, bucket := range c.S3Config.GetReplicatedAttachmentBuckets(string(row.AttachmentType)) {
		wantInBucketIDs[bucket] = true
	}
	delete(wantInBucketIDs, row.LatestBucket)
	for _, bucket := range row.ReplicatedBuckets {
		delete(wantInBucketIDs, bucket)
	}
	if len(wantInBucketIDs) == 0 {
		return c.Repo.MarkAttachmentReplicationAsDone(ctx, row)
	}
	for bucketID := range wantInBucketIDs {
		if err := c.Repo.RegisterReplicationAttempt(ctx, row, bucketID); err != nil {
			return stacktrace.Propagate(err, "could not register attachment replication attempt")
		}
		if err := c.replicateAttachmentFn(ctx, row, bucketID); err != nil {
			return stacktrace.Propagate(err, "failed to replicate attachment")
		}
		if err := c.Repo.MoveBetweenBuckets(row, bucketID, contactrepo.InflightRepColumn, contactrepo.ReplicationColumn); err != nil {
			return err
		}
	}
	return c.Repo.MarkAttachmentReplicationAsDone(ctx, row)
}

func (c *Controller) startDeleteWorkers(n int) {
	log.Infof("Starting %d delete workers for contact attachments", n)
	for i := 0; i < n; i++ {
		go c.delete(i)
		time.Sleep(time.Duration(2*i+1) * time.Minute)
	}
}

func (c *Controller) delete(i int) {
	for {
		if err := c.tryDelete(); err != nil {
			time.Sleep(time.Duration(i+5) * time.Minute)
		}
	}
}

func (c *Controller) tryDelete() error {
	newLockTime := enteTime.MicrosecondsAfterMinutes(10)
	row, err := c.Repo.GetPendingSyncAttachmentAndExtendLock(context.Background(), newLockTime, true)
	if err != nil {
		return err
	}
	return c.deleteAttachmentRow(*row)
}

func (c *Controller) deleteAttachmentRow(row contactmodel.Attachment) error {
	if !row.IsDeleted {
		return stacktrace.NewError("attachment is not marked as deleted")
	}
	bucketColumnMap, err := getAttachmentBucketColumnMap(row)
	if err != nil {
		return err
	}
	for bucketID, columnName := range bucketColumnMap {
		if err := c.deleteAttachmentFn(row, bucketID); err != nil {
			return stacktrace.Propagate(err, "failed to delete attachment from bucket")
		}
		if err := c.Repo.RemoveBucket(row, bucketID, columnName); err != nil {
			return stacktrace.Propagate(err, "failed to remove attachment bucket from db")
		}
	}
	if err := c.deleteAttachmentFn(row, row.LatestBucket); err != nil {
		return stacktrace.Propagate(err, "failed to delete latest attachment object")
	}
	return c.Repo.DeleteAttachment(context.Background(), row)
}

func getAttachmentBucketColumnMap(row contactmodel.Attachment) (map[string]string, error) {
	bucketColumnMap := make(map[string]string)
	for _, bucketID := range row.DeleteFromBuckets {
		if existingColumn, exists := bucketColumnMap[bucketID]; exists {
			return nil, stacktrace.NewError("duplicate delete bucket %s in %s", bucketID, existingColumn)
		}
		bucketColumnMap[bucketID] = contactrepo.DeletionColumn
	}
	for _, bucketID := range row.ReplicatedBuckets {
		if existingColumn, exists := bucketColumnMap[bucketID]; exists {
			return nil, stacktrace.NewError("duplicate replicated bucket %s in %s", bucketID, existingColumn)
		}
		bucketColumnMap[bucketID] = contactrepo.ReplicationColumn
	}
	for _, bucketID := range row.InflightRepBuckets {
		if existingColumn, exists := bucketColumnMap[bucketID]; exists {
			return nil, stacktrace.NewError("duplicate inflight bucket %s in %s", bucketID, existingColumn)
		}
		bucketColumnMap[bucketID] = contactrepo.InflightRepColumn
	}
	return bucketColumnMap, nil
}

func (c *Controller) replicateAttachmentObject(ctx context.Context, row contactmodel.Attachment, dstBucketID string) error {
	if err := fileutil.EnsureSufficientSpace(row.Size); err != nil {
		return stacktrace.Propagate(err, "")
	}
	filePath, file, err := fileutil.CreateTemporaryFile(c.tempStorage, row.AttachmentID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to create temporary file")
	}
	defer os.Remove(filePath)
	defer file.Close()

	downloader := c.downloadManagerCache[row.LatestBucket]
	if downloader == nil {
		s3Client := c.S3Config.GetS3Client(row.LatestBucket)
		downloader = s3manager.NewDownloaderWithClient(&s3Client)
	}
	_, err = downloader.DownloadWithContext(ctx, file, &s3.GetObjectInput{
		Bucket: c.S3Config.GetBucket(row.LatestBucket),
		Key:    aws.String(row.ObjectKey()),
	})
	if err != nil {
		return stacktrace.Propagate(err, "failed to download attachment from bucket %s", row.LatestBucket)
	}
	if err := c.verifyAttachmentSize(row.LatestBucket, row.ObjectKey(), row.Size); err != nil {
		return err
	}
	dstClient := c.S3Config.GetS3Client(dstBucketID)
	uploader := s3manager.NewUploaderWithClient(&dstClient)
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return stacktrace.Propagate(err, "failed to seek temporary attachment file")
	}
	if _, err := uploader.Upload(&s3manager.UploadInput{
		Bucket: c.S3Config.GetBucket(dstBucketID),
		Key:    aws.String(row.ObjectKey()),
		Body:   file,
	}); err != nil {
		return stacktrace.Propagate(err, "failed to upload attachment to bucket %s", dstBucketID)
	}
	return c.verifyAttachmentSize(dstBucketID, row.ObjectKey(), row.Size)
}

func (c *Controller) verifyAttachmentSize(bucketID string, objectKey string, expectedSize int64) error {
	s3Client := c.S3Config.GetS3Client(bucketID)
	res, err := s3Client.HeadObject(&s3.HeadObjectInput{
		Bucket: c.S3Config.GetBucket(bucketID),
		Key:    aws.String(objectKey),
	})
	if err != nil {
		return stacktrace.Propagate(err, "failed to fetch attachment info from bucket %s", bucketID)
	}
	if *res.ContentLength != expectedSize {
		return stacktrace.NewError("attachment size does not match expected size")
	}
	return nil
}

func (c *Controller) deleteAttachmentObject(row contactmodel.Attachment, bucketID string) error {
	return c.ObjectCleanupController.DeleteObjectFromDataCenter(row.ObjectKey(), bucketID)
}
