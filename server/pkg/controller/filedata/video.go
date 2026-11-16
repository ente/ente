package filedata

import (
	"context"
	"database/sql"
	"errors"
	"strings"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/filedata"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/network"
	"github.com/ente/stacktrace"
	"github.com/gin-contrib/requestid"
	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
)

func (c *Controller) InsertVideoPreview(ctx *gin.Context, req *filedata.VidPreviewRequest) error {
	if err := req.Validate(); err != nil {
		return stacktrace.Propagate(err, "validation failed")
	}
	userID := auth.GetUserID(ctx.Request.Header)
	err := c._checkPreviewWritePerm(ctx, req.FileID, userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	fileOwnerID := userID

	fileObjectKey := filedata.ObjectKey(req.FileID, fileOwnerID, ente.PreviewVideo, &req.ObjectID)
	objectKey := filedata.ObjectMetadataKey(req.FileID, fileOwnerID, ente.PreviewVideo, &req.ObjectID)
	bucketID, err := c.Repo.ObjectCleanupRepo.GetPreviewUploadBucket(ctx, fileObjectKey, userID, auth.GetApp(ctx))
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			registered, checkErr := c.isRegisteredPreviewRetry(ctx, req, userID)
			if checkErr != nil {
				return stacktrace.Propagate(checkErr, "failed to check for a previous preview registration")
			}
			if registered {
				return nil
			}
			return stacktrace.Propagate(ente.NewBadRequestWithMessage("staged upload not found"), "")
		}
		return stacktrace.Propagate(err, "failed to find staged preview upload")
	}
	if !c.S3Config.IsBucketActive(bucketID) {
		return stacktrace.NewError("upload bucket %q is not configured", bucketID)
	}

	if sizeErr := c.verifySize(bucketID, fileObjectKey, req.ObjectSize); sizeErr != nil {
		return stacktrace.Propagate(sizeErr, "failed to validate size")
	}
	if err := c.checkVideoPreviewSize(ctx, req, userID, log.WithFields(log.Fields{
		"req_id":              requestid.Get(ctx),
		"size_check_stage":    "registration",
		"preview_size_source": "verified",
	})); err != nil {
		return err
	}

	obj := filedata.S3FileMetadata{
		Version:          *req.Version,
		EncryptedData:    req.Playlist,
		DecryptionHeader: req.PlayListHeader,
		Client:           network.GetClientInfo(ctx),
	}
	logger := log.
		WithField("objectKey", objectKey).
		WithField("fileID", req.FileID).
		WithField("type", ente.PreviewVideo)

	size, uploadErr := c.uploadObject(obj, objectKey, bucketID)
	if uploadErr != nil {
		logger.WithError(uploadErr).Error("upload failed")
		return stacktrace.Propagate(uploadErr, "failed to upload video preview metadata")
	}
	row := filedata.Row{
		FileID:       req.FileID,
		Type:         ente.PreviewVideo,
		UserID:       fileOwnerID,
		Size:         size + req.ObjectSize,
		LatestBucket: bucketID,
		ObjectID:     &req.ObjectID,
		ObjectNonce:  nil,
		ObjectSize:   &req.ObjectSize,
	}
	dbInsertErr := c.Repo.InsertOrUpdatePreviewData(context.Background(), row, fileObjectKey)
	if dbInsertErr != nil {
		if strings.Contains(dbInsertErr.Error(), "failed to remove object from tempObjects") {
			isDuplicate, checkErr := c._checkIfDuplicateRequest(ctx, row, fileObjectKey)
			if checkErr != nil {
				logger.WithError(checkErr).Error("failed to check for duplicate request")
			}
			if isDuplicate {
				logger.Info("duplicate put request detected, ignoring")
				return nil
			}
		}
		return stacktrace.Propagate(dbInsertErr, "failed to insert or update preview data")
	}
	return nil
}

func (c *Controller) isRegisteredPreviewRetry(ctx *gin.Context, req *filedata.VidPreviewRequest, userID int64) (bool, error) {
	data, err := c.Repo.GetFilesData(ctx, ente.PreviewVideo, []int64{req.FileID})
	if err != nil {
		return false, err
	}
	if len(data) != 1 {
		return false, nil
	}
	row := data[0]
	return !row.IsDeleted && row.UserID == userID && row.ObjectID != nil &&
		row.ObjectSize != nil && *row.ObjectID == req.ObjectID && *row.ObjectSize == req.ObjectSize, nil
}

func (c *Controller) checkVideoPreviewSize(ctx context.Context, req *filedata.VidPreviewRequest, userID int64, logger *log.Entry) error {
	logger = logger.WithFields(log.Fields{
		"file_id":            req.FileID,
		"user_id":            userID,
		"preview_size_bytes": req.ObjectSize,
	})
	fileIDs := []int64{req.FileID}
	infos, err := c.FileRepo.GetFilesInfo(ctx, fileIDs, userID)
	if err != nil {
		logger.WithField("size_limit_enforced", false).WithError(err).Warn("could not check video preview size limit")
		return nil
	}
	info := infos[req.FileID]
	if info == nil || info.FileSize <= 0 {
		infos, err = c.FileRepo.GetFileInfoFromObjectKeys(ctx, fileIDs)
		if err != nil {
			logger.WithField("size_limit_enforced", false).WithError(err).Warn("could not check video preview size limit")
			return nil
		}
		info = infos[req.FileID]
	}
	if info == nil {
		return checkVideoPreviewSizeAgainstOriginal(logger, req, 0)
	}
	return checkVideoPreviewSizeAgainstOriginal(logger, req, info.FileSize)
}

func checkVideoPreviewSizeAgainstOriginal(logger *log.Entry, req *filedata.VidPreviewRequest, originalSize int64) error {
	logger = logger.WithFields(log.Fields{
		"file_id":             req.FileID,
		"original_size_bytes": originalSize,
		"preview_size_bytes":  req.ObjectSize,
	})
	if originalSize <= 0 {
		logger.WithField("size_limit_enforced", false).Warn("video preview size check missing original size")
		return nil
	}
	if err := req.ValidateSize(originalSize); err != nil {
		logger.WithFields(log.Fields{
			"preview_original_ratio": float64(req.ObjectSize) / float64(originalSize),
			"size_limit_enforced":    true,
		}).
			Warn("video preview exceeds size limit")
		return err
	}
	return nil
}

func (c *Controller) _checkIfDuplicateRequest(ctx *gin.Context, row filedata.Row, fileObjectKey string) (bool, error) {
	exists, err := c.Repo.ObjectCleanupRepo.DoesTempObjectExist(ctx, fileObjectKey, row.LatestBucket)
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to check if duplicate request")
	}
	if exists {
		return false, nil
	}
	data, dataErr := c.Repo.GetFilesData(ctx, row.Type, []int64{row.FileID})
	if dataErr != nil {
		return false, stacktrace.Propagate(dataErr, "failed to get files data")
	}
	if len(data) == 0 {
		return false, nil
	}
	if len(data) > 1 {
		return false, stacktrace.NewError("multiple rows found for fileID %d", row.FileID)
	}
	if data[0].LatestBucket == row.LatestBucket &&
		data[0].ObjectID != nil && *data[0].ObjectID == *row.ObjectID &&
		data[0].ObjectSize != nil && *data[0].ObjectSize == *row.ObjectSize {
		log.WithField("fileID", row.FileID).WithField("objectID", row.ObjectID).
			Info("duplicate put request detected")
		return true, nil
	} else {
		log.WithField("fileID", row.FileID).WithField("objectID", row.ObjectID).
			Info("duplicate put request not detected, existing data does not match")
	}
	return false, nil
}
