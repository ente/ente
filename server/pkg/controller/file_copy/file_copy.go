package file_copy

import (
	"fmt"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/controller/collections"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/s3config"
	enteTime "github.com/ente/museum/pkg/utils/time"
	"github.com/gin-contrib/requestid"
	"github.com/gin-gonic/gin"
	"github.com/sirupsen/logrus"
	"golang.org/x/sync/errgroup"
	"sync"
	"time"
)

const ()

type FileCopyController struct {
	S3Config       *s3config.S3Config
	FileController *controller.FileController
	FileRepo       *repo.FileRepository
	CollectionCtrl *collections.CollectionController
	ObjectRepo     *repo.ObjectRepository
}

type copyS3ObjectReq struct {
	SourceS3Object ente.S3ObjectKey
	DestObjectKey  string
}

type fileCopyInternal struct {
	SourceFile       ente.File
	DestCollectionID int64
	// The FileKey is encrypted with the destination collection's key
	EncryptedFileKey      string
	EncryptedFileKeyNonce string
	FileCopyReq           *copyS3ObjectReq
	ThumbCopyReq          *copyS3ObjectReq
}

func (fci fileCopyInternal) newFile(ownedID int64) ente.File {
	newFileAttributes := fci.SourceFile.File
	newFileAttributes.ObjectKey = fci.FileCopyReq.DestObjectKey
	newThumbAttributes := fci.SourceFile.Thumbnail
	newThumbAttributes.ObjectKey = fci.ThumbCopyReq.DestObjectKey
	return ente.File{
		OwnerID:            ownedID,
		CollectionID:       fci.DestCollectionID,
		EncryptedKey:       fci.EncryptedFileKey,
		KeyDecryptionNonce: fci.EncryptedFileKeyNonce,
		File:               newFileAttributes,
		Thumbnail:          newThumbAttributes,
		Metadata:           fci.SourceFile.Metadata,
		PubicMagicMetadata: fci.SourceFile.PubicMagicMetadata,
		UpdationTime:       enteTime.Microseconds(),
		IsDeleted:          false,
	}
}

func (fc *FileCopyController) CopyFiles(c *gin.Context, req ente.CopyFileSyncRequest) (*ente.CopyResponse, error) {
	userID := auth.GetUserID(c.Request.Header)
	app := auth.GetApp(c)
	logger := logrus.WithFields(logrus.Fields{"req_id": requestid.Get(c), "user_id": userID})
	err := fc.CollectionCtrl.IsCopyAllowed(c, userID, req)
	if err != nil {
		return nil, err
	}
	fileIDs := make([]int64, 0, len(req.CollectionFileItems))
	fileToCollectionFileMap := make(map[int64]*ente.CollectionFileItem, len(req.CollectionFileItems))
	for i := range req.CollectionFileItems {
		item := &req.CollectionFileItems[i]
		fileToCollectionFileMap[item.ID] = item
		fileIDs = append(fileIDs, item.ID)
	}
	s3ObjectsToCopy, err := fc.ObjectRepo.GetObjectsForFileIDs(fileIDs)
	if err != nil {
		return nil, err
	}
	// note: this assumes that preview existingFilesToCopy for videos are not tracked inside the object_keys table
	if len(s3ObjectsToCopy) != 2*len(fileIDs) {
		return nil, ente.NewInternalError(fmt.Sprintf("expected %d objects, got %d", 2*len(fileIDs), len(s3ObjectsToCopy)))
	}
	// todo:(neeraj) if the total size is greater than 1GB, do an early check if the user can upload the existingFilesToCopy
	var totalSize int64
	for _, obj := range s3ObjectsToCopy {
		totalSize += obj.FileSize
	}
	logger.WithField("totalSize", totalSize).Info("total size of existingFilesToCopy to copy")

	// request the uploadUrls using existing method. This is to ensure that orphan objects are automatically cleaned up
	// todo:(neeraj) optimize this method by removing the need for getting a signed url for each object
	uploadUrls, err := fc.FileController.GetUploadURLs(c, userID, len(s3ObjectsToCopy), app, true)
	if err != nil {
		return nil, err
	}
	existingFilesToCopy, err := fc.FileRepo.GetFileAttributesForCopy(fileIDs)
	if err != nil {
		return nil, err
	}
	if len(existingFilesToCopy) != len(fileIDs) {
		return nil, ente.NewInternalError(fmt.Sprintf("expected %d existingFilesToCopy, got %d", len(fileIDs), len(existingFilesToCopy)))
	}
	fileOGS3Object := make(map[int64]*copyS3ObjectReq)
	fileThumbS3Object := make(map[int64]*copyS3ObjectReq)
	for i, s3Obj := range s3ObjectsToCopy {
		if s3Obj.Type == ente.FILE {
			fileOGS3Object[s3Obj.FileID] = &copyS3ObjectReq{
				SourceS3Object: s3Obj,
				DestObjectKey:  uploadUrls[i].ObjectKey,
			}
		} else if s3Obj.Type == ente.THUMBNAIL {
			fileThumbS3Object[s3Obj.FileID] = &copyS3ObjectReq{
				SourceS3Object: s3Obj,
				DestObjectKey:  uploadUrls[i].ObjectKey,
			}
		} else {
			return nil, ente.NewInternalError(fmt.Sprintf("unexpected object type %s", s3Obj.Type))
		}
	}
	fileCopyList := make([]fileCopyInternal, 0, len(existingFilesToCopy))
	for i := range existingFilesToCopy {
		file := existingFilesToCopy[i]
		collectionItem := fileToCollectionFileMap[file.ID]
		if collectionItem.ID != file.ID {
			return nil, ente.NewInternalError(fmt.Sprintf("expected collectionItem.ID %d, got %d", file.ID, collectionItem.ID))
		}
		fileCopy := fileCopyInternal{
			SourceFile:            file,
			DestCollectionID:      req.DstCollection,
			EncryptedFileKey:      fileToCollectionFileMap[file.ID].EncryptedKey,
			EncryptedFileKeyNonce: fileToCollectionFileMap[file.ID].KeyDecryptionNonce,
			FileCopyReq:           fileOGS3Object[file.ID],
			ThumbCopyReq:          fileThumbS3Object[file.ID],
		}
		fileCopyList = append(fileCopyList, fileCopy)
	}
	oldToNewFileIDMap := make(map[int64]int64)
	var mapMutex sync.Mutex
	var wg sync.WaitGroup
	errChan := make(chan error, len(fileCopyList))

	for _, fileCopy := range fileCopyList {
		wg.Go(func() {
			newFile, err := fc.createCopy(c, fileCopy, userID, app)
			if err != nil {
				errChan <- err
				return
			}
			mapMutex.Lock()
			oldToNewFileIDMap[fileCopy.SourceFile.ID] = newFile.ID
			mapMutex.Unlock()
		})
	}

	// Wait for all goroutines to finish
	wg.Wait()

	// Close the error channel and check if there were any errors
	close(errChan)
	if err, ok := <-errChan; ok {
		return nil, err
	}
	return &ente.CopyResponse{OldToNewFileIDMap: oldToNewFileIDMap}, nil
}

func (fc *FileCopyController) createCopy(c *gin.Context, fcInternal fileCopyInternal, userID int64, app ente.App) (*ente.File, error) {
	// using HotS3Client copy the File and Thumbnail
	s3Client := fc.S3Config.GetHotS3Client()
	hotBucket := fc.S3Config.GetHotBucket()
	g := new(errgroup.Group)
	g.Go(func() error {
		return copyS3Object(s3Client, hotBucket, fcInternal.FileCopyReq)
	})
	g.Go(func() error {
		return copyS3Object(s3Client, hotBucket, fcInternal.ThumbCopyReq)
	})
	if err := g.Wait(); err != nil {
		return nil, err
	}
	file := fcInternal.newFile(userID)
	newFile, err := fc.FileController.Create(c, userID, file, "", app)
	if err != nil {
		return nil, err
	}
	return &newFile, nil
}

// Helper function for S3 object copying.
func copyS3Object(s3Client *s3.S3, bucket *string, req *copyS3ObjectReq) error {
	copySource := fmt.Sprintf("%s/%s", *bucket, req.SourceS3Object.ObjectKey)
	copyInput := &s3.CopyObjectInput{
		Bucket:     bucket,
		CopySource: &copySource,
		Key:        &req.DestObjectKey,
	}
	start := time.Now()
	_, err := s3Client.CopyObject(copyInput)
	elapsed := time.Since(start)
	if err != nil {
		return fmt.Errorf("failed to copy (%s) from %s to %s: %w", req.SourceS3Object.Type, copySource, req.DestObjectKey, err)
	}
	logrus.WithField("duration", elapsed).WithField("size", req.SourceS3Object.FileSize).Infof("copied (%s) from %s to %s", req.SourceS3Object.Type, copySource, req.DestObjectKey)
	return nil
}
