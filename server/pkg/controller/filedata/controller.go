package filedata

import (
	"context"
	"errors"
	"fmt"
	"slices"

	"github.com/aws/aws-sdk-go/aws/awserr"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/aws/aws-sdk-go/service/s3/s3manager"
	"github.com/ente/museum/ente"
	fileData "github.com/ente/museum/ente/filedata"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/controller/access"
	"github.com/ente/museum/pkg/controller/discord"
	"github.com/ente/museum/pkg/repo"
	fileDataRepo "github.com/ente/museum/pkg/repo/filedata"
	"github.com/ente/museum/pkg/utils/array"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/network"
	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/ente/stacktrace"
	"github.com/gin-contrib/requestid"
	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
	"net/http"
	"strings"
	"sync"
	gTime "time"
)

// _fetchConfig is the configuration for the fetching objects from S3
type _fetchConfig struct {
	RetryCount     int
	InitialTimeout gTime.Duration
	MaxTimeout     gTime.Duration
}

var _defaultFetchConfig = _fetchConfig{RetryCount: 3, InitialTimeout: 10 * gTime.Second, MaxTimeout: 30 * gTime.Second}
var globalFileFetchSemaphore = make(chan struct{}, 400)

type bulkS3MetaFetchResult struct {
	s3MetaObject fileData.S3FileMetadata
	dbEntry      fileData.Row
	err          error
}

type Controller struct {
	Repo                    *fileDataRepo.Repository
	AccessCtrl              access.Controller
	ObjectCleanupController *controller.ObjectCleanupController
	S3Config                *s3config.S3Config
	FileRepo                *repo.FileRepository
	CollectionRepo          *repo.CollectionRepository
	DiscordController       *discord.DiscordController
	downloadManagerCache    map[string]*s3manager.Downloader
	// for downloading objects from s3 for replication
	workerURL   string
	tempStorage string
}

func New(repo *fileDataRepo.Repository,
	accessCtrl access.Controller,
	objectCleanupController *controller.ObjectCleanupController,
	s3Config *s3config.S3Config,
	fileRepo *repo.FileRepository,
	collectionRepo *repo.CollectionRepository,
	discordController *discord.DiscordController,
) *Controller {
	embeddingDcs := []string{s3Config.GetHotBackblazeDC(), s3Config.GetHotWasabiDC(), s3Config.GetWasabiDerivedDC(), s3Config.GetDerivedStorageDataCenter(), "b5", "b6"}
	cache := make(map[string]*s3manager.Downloader, len(embeddingDcs))
	for i := range embeddingDcs {
		s3Client := s3Config.GetS3Client(embeddingDcs[i])
		cache[embeddingDcs[i]] = s3manager.NewDownloaderWithClient(&s3Client)
	}
	return &Controller{
		Repo:                    repo,
		AccessCtrl:              accessCtrl,
		ObjectCleanupController: objectCleanupController,
		S3Config:                s3Config,
		FileRepo:                fileRepo,
		CollectionRepo:          collectionRepo,
		DiscordController:       discordController,
		downloadManagerCache:    cache,
	}
}

func (c *Controller) InsertOrUpdateMetadata(ctx *gin.Context, req *fileData.PutFileDataRequest) error {
	if err := req.Validate(); err != nil {
		return stacktrace.Propagate(err, "validation failed")
	}
	userID := auth.GetUserID(ctx.Request.Header)
	fileOwnerID, err := c.FileRepo.GetOwnerID(req.FileID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if fileOwnerID != userID {
		permErr := c._checkMetadataReadOrWritePerm(ctx, userID, []int64{req.FileID})
		if permErr != nil {
			return stacktrace.Propagate(permErr, "")
		}
	}
	if req.Type != ente.MlData {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("unsupported object type "+string(req.Type)), "")
	}
	if versionErr := c._validateLastUpdatedAt(ctx, req.LastUpdatedAt, req.FileID, req.Type); versionErr != nil {
		return stacktrace.Propagate(versionErr, "")
	}

	bucketID := c.S3Config.GetBucketID(req.Type)
	objectKey := fileData.ObjectMetadataKey(req.FileID, fileOwnerID, req.Type, nil)
	obj := fileData.S3FileMetadata{
		Version:          *req.Version,
		EncryptedData:    *req.EncryptedData,
		DecryptionHeader: *req.DecryptionHeader,
		Client:           network.GetClientInfo(ctx),
	}
	// Start a goroutine to handle the upload and insert operations
	//go func() {
	logger := log.WithField("objectKey", objectKey).WithField("fileID", req.FileID).WithField("type", req.Type)
	size, uploadErr := c.uploadObject(obj, objectKey, bucketID)
	if uploadErr != nil {
		logger.WithError(uploadErr).Error("upload failed")
		return uploadErr
	}

	row := fileData.Row{
		FileID:       req.FileID,
		Type:         req.Type,
		UserID:       fileOwnerID,
		Size:         size,
		LatestBucket: bucketID,
	}
	dbInsertErr := c.Repo.InsertOrUpdate(context.Background(), row)
	if dbInsertErr != nil {
		logger.WithError(dbInsertErr).Error("insert or update failed")
		return stacktrace.Propagate(dbInsertErr, "failed to insert or update file data row")
	}
	//}()
	return nil
}

func (c *Controller) GetFileData(ctx *gin.Context, actorUser int64, req fileData.GetFileData) (*fileData.Entity, error) {
	if err := req.Validate(); err != nil {
		return nil, stacktrace.Propagate(err, "validation failed")
	}
	if err := c._checkMetadataReadOrWritePerm(ctx, actorUser, []int64{req.FileID}); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	doRows, err := c.Repo.GetFilesData(ctx, req.Type, []int64{req.FileID})
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if len(doRows) == 0 || doRows[0].IsDeleted {
		if req.PreferNoContent {
			return nil, nil
		}
		return nil, stacktrace.Propagate(&ente.ErrNotFoundError, "")
	}
	ctxLogger := log.WithFields(log.Fields{
		"objectKey":     doRows[0].S3FileMetadataObjectKey(),
		"latest_bucket": doRows[0].LatestBucket,
		"req_id":        requestid.Get(ctx),
		"file_id":       req.FileID,
	})
	s3MetaObject, err := c.fetchS3FileMetadata(context.Background(), doRows[0], ctxLogger)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &fileData.Entity{
		FileID:           doRows[0].FileID,
		Type:             doRows[0].Type,
		EncryptedData:    s3MetaObject.EncryptedData,
		DecryptionHeader: s3MetaObject.DecryptionHeader,
		UpdatedAt:        doRows[0].UpdatedAt,
	}, nil
}

func (c *Controller) GetFilesData(ctx *gin.Context, req fileData.GetFilesData) (*fileData.GetFilesDataResponse, error) {
	userID := auth.GetUserID(ctx.Request.Header)
	if err := req.Validate(); err != nil {
		return nil, stacktrace.Propagate(err, "req validation failed")
	}
	if err := c._checkMetadataReadOrWritePerm(ctx, userID, req.FileIDs); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}

	doRows, err := c.Repo.GetFilesData(ctx, req.Type, req.FileIDs)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}

	activeRows := make([]fileData.Row, 0)
	dbFileIds := make([]int64, 0)
	errFileIds := make([]int64, 0)
	for i := range doRows {
		dbFileIds = append(dbFileIds, doRows[i].FileID)
		if !doRows[i].IsDeleted {
			activeRows = append(activeRows, doRows[i])
		}
	}
	pendingIndexFileIds := array.FindMissingElementsInSecondList(req.FileIDs, dbFileIds)
	// Fetch missing doRows in parallel
	s3MetaFetchResults, err := c.getS3FileMetadataParallel(ctx, activeRows)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	fetchedEmbeddings := make([]fileData.Entity, 0)

	// Populate missing data in doRows from fetched objects
	for _, obj := range s3MetaFetchResults {
		if obj.err != nil {
			errFileIds = append(errFileIds, obj.dbEntry.FileID)
		} else {
			fetchedEmbeddings = append(fetchedEmbeddings, fileData.Entity{
				FileID:           obj.dbEntry.FileID,
				Type:             obj.dbEntry.Type,
				EncryptedData:    obj.s3MetaObject.EncryptedData,
				DecryptionHeader: obj.s3MetaObject.DecryptionHeader,
				UpdatedAt:        obj.dbEntry.UpdatedAt,
			})
		}
	}

	return &fileData.GetFilesDataResponse{
		Data:                fetchedEmbeddings,
		PendingIndexFileIDs: pendingIndexFileIds,
		ErrFileIDs:          errFileIds,
	}, nil
}

func (c *Controller) getS3FileMetadataParallel(ctx *gin.Context, dbRows []fileData.Row) ([]bulkS3MetaFetchResult, error) {
	var wg sync.WaitGroup
	embeddingObjects := make([]bulkS3MetaFetchResult, len(dbRows))
	for i := range dbRows {
		index := i
		dbRow := dbRows[i]
		globalFileFetchSemaphore <- struct{}{} // Acquire from global semaphore
		wg.Go(func() {
			defer func() { <-globalFileFetchSemaphore }() // Release back to global semaphore

			ctxLogger := log.WithFields(log.Fields{
				"objectKey":     dbRow.S3FileMetadataObjectKey(),
				"req_id":        requestid.Get(ctx),
				"latest_bucket": dbRow.LatestBucket,
				"file_id":       dbRow.FileID,
			})

			s3FileMetadata, err := c.fetchS3FileMetadata(context.Background(), dbRow, ctxLogger)
			if err != nil {
				ctxLogger.
					Error("error fetching  object: "+dbRow.S3FileMetadataObjectKey(), err)
				embeddingObjects[index] = bulkS3MetaFetchResult{
					err:     err,
					dbEntry: dbRow,
				}

			} else {
				embeddingObjects[index] = bulkS3MetaFetchResult{
					s3MetaObject: *s3FileMetadata,
					dbEntry:      dbRow,
				}
			}
		})
	}
	wg.Wait()
	return embeddingObjects, nil
}

func (c *Controller) fetchS3FileMetadata(ctx context.Context, row fileData.Row, ctxLogger *log.Entry) (*fileData.S3FileMetadata, error) {
	dc := row.LatestBucket
	preferredBucket := c.S3Config.GetBucketID(row.Type)
	// If the current primary bucket is different from the latest bucket where data was written,
	// check and use the preferred bucket if the data is replicated there.
	if !strings.EqualFold(preferredBucket, dc) {
		if slices.Contains(row.ReplicatedBuckets, preferredBucket) {
			dc = preferredBucket
		}
	}
	opt := _defaultFetchConfig
	objectKey := row.S3FileMetadataObjectKey()
	totalAttempts := opt.RetryCount + 1
	timeout := opt.InitialTimeout
	for i := 0; i < totalAttempts; i++ {
		if i > 0 {
			timeout = min(timeout*2, opt.MaxTimeout)
		}
		fetchCtx, cancel := context.WithTimeout(ctx, timeout)
		select {
		case <-ctx.Done():
			cancel()
			return nil, stacktrace.Propagate(ctx.Err(), "")
		default:
			obj, err := c.downloadObject(fetchCtx, objectKey, dc)
			cancel() // Ensure cancel is called to release resources
			if err == nil {
				if i > 0 {
					ctxLogger.WithField("dc", dc).Infof("Fetched object after %d attempts", i)
				}
				return &obj, nil
			}
			// Check if the error is due to context timeout or cancellation
			if err == nil && fetchCtx.Err() != nil {
				ctxLogger.WithField("dc", dc).Error("Fetch timed out or cancelled: ", fetchCtx.Err())
			} else {
				// check if the error is due to object not found
				if s3Err, ok := err.(awserr.RequestFailure); ok {
					if s3Err.Code() == s3.ErrCodeNoSuchKey {
						return nil, stacktrace.Propagate(errors.New("object not found"), "")
					}
				}
				ctxLogger.WithField("dc", dc).Error("Failed to fetch object: ", err)
			}
		}
	}
	return nil, stacktrace.Propagate(errors.New("failed to fetch object"), "")
}

func (c *Controller) _checkMetadataReadOrWritePerm(ctx *gin.Context, userID int64, fileIDs []int64) error {
	if err := c.AccessCtrl.CanAccessFile(ctx, &access.CanAccessFileParams{
		ActorUserID: userID,
		FileIDs:     fileIDs,
	}); err != nil {
		return stacktrace.Propagate(err, "User does not own some file(s)")
	}
	return nil
}

func (c *Controller) _validateLastUpdatedAt(ctx *gin.Context, lastUpdatedAt *int64, fileID int64, oType ente.ObjectType) error {
	if lastUpdatedAt == nil {
		return nil
	}
	doRows, err := c.Repo.GetFilesData(ctx, oType, []int64{fileID})
	if err != nil {
		return stacktrace.Propagate(err, "failed to get data")
	}
	var invalidVersionErr = &ente.ApiError{
		HttpStatusCode: http.StatusConflict,
		Code:           "INVALID_VERSION",
		Message:        "",
	}
	if len(doRows) == 0 {
		if *lastUpdatedAt == 0 {
			return nil
		}
		invalidVersionErr.Message = "non zero version empty data"
		return invalidVersionErr
	}
	if doRows[0].IsDeleted {
		invalidVersionErr.Message = "data deleted"
		return invalidVersionErr
	}
	dbUpdatedAt := doRows[0].UpdatedAt
	if dbUpdatedAt != *lastUpdatedAt {
		invalidVersionErr.Message = fmt.Sprintf("version mismatch expected %d, found %d", dbUpdatedAt, *lastUpdatedAt)
		return invalidVersionErr
	}
	return nil
}

// _checkPreviewWritePerm is
func (c *Controller) _checkPreviewWritePerm(ctx *gin.Context, fileID int64, actorID int64) error {
	err := c.AccessCtrl.VerifyFileOwnership(ctx, &access.VerifyFileOwnershipParams{
		ActorUserId: actorID,
		FileIDs:     []int64{fileID},
	})
	if err != nil {
		return stacktrace.Propagate(err, "User does not own file")
	}
	count, err := c.CollectionRepo.GetCollectionCount(fileID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if count < 1 {
		return stacktrace.Propagate(ente.ErrNotFound, "")
	}
	return nil
}

func (c *Controller) FileDataStatusDiff(ctx *gin.Context, req fileData.FDDiffRequest) ([]fileData.FDStatus, error) {
	userID := auth.GetUserID(ctx.Request.Header)
	return c.Repo.GetFDForUser(ctx, userID, *req.LastUpdatedAt, 5000)
}
