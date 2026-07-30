package filedata

import (
	"context"
	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/filedata"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/network"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
	"strings"
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

	bucketID := c.S3Config.GetBucketID(ente.PreviewVideo)
	fileObjectKey := filedata.ObjectKey(req.FileID, fileOwnerID, ente.PreviewVideo, &req.ObjectID)
	objectKey := filedata.ObjectMetadataKey(req.FileID, fileOwnerID, ente.PreviewVideo, &req.ObjectID)

	if sizeErr := c.verifySize(bucketID, fileObjectKey, req.ObjectSize); sizeErr != nil {
		return stacktrace.Propagate(sizeErr, "failed to validate size")
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
				// continue with existing dbInsertErr
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
