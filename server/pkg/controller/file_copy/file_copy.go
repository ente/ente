package file_copy

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/aws/aws-sdk-go/aws"
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
)

const (
	maxSingleCopySize     int64 = 5_000_000_000
	multipartCopyPartSize       = 1 << 30
	multipartAbortTimeout       = 30 * time.Second
)

type FileCopyController struct {
	S3Config          *s3config.S3Config
	FileController    *controller.FileController
	FileRepo          *repo.FileRepository
	CollectionCtrl    *collections.CollectionController
	ObjectRepo        *repo.ObjectRepository
	ObjectCleanupRepo *repo.ObjectCleanupRepository
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
	// Video previews are not tracked in object_keys.
	if len(s3ObjectsToCopy) != 2*len(fileIDs) {
		return nil, ente.NewInternalError(fmt.Sprintf("expected %d objects, got %d", 2*len(fileIDs), len(s3ObjectsToCopy)))
	}
	// todo:(neeraj) if the total size is greater than 1GB, do an early check if the user can upload the existingFilesToCopy
	var totalSize int64
	for _, obj := range s3ObjectsToCopy {
		totalSize += obj.FileSize
	}
	logger.WithField("totalSize", totalSize).Info("total size of existingFilesToCopy to copy")

	// Reuse upload URLs so abandoned copies are cleaned up as orphan objects.
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

	wg.Wait()

	close(errChan)
	if err, ok := <-errChan; ok {
		return nil, err
	}
	return &ente.CopyResponse{OldToNewFileIDMap: oldToNewFileIDMap}, nil
}

func (fc *FileCopyController) createCopy(c *gin.Context, fcInternal fileCopyInternal, userID int64, app ente.App) (*ente.File, error) {
	s3Client := fc.S3Config.GetHotS3Client()
	hotBucket := fc.S3Config.GetHotBucket()
	hotDC := fc.S3Config.GetHotDataCenter()
	g := new(errgroup.Group)
	g.Go(func() error {
		return copyS3Object(c.Request.Context(), s3Client, hotBucket, hotDC, fc.ObjectCleanupRepo, fcInternal.FileCopyReq)
	})
	g.Go(func() error {
		return copyS3Object(c.Request.Context(), s3Client, hotBucket, hotDC, fc.ObjectCleanupRepo, fcInternal.ThumbCopyReq)
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

func copyS3Object(ctx context.Context, s3Client *s3.S3, bucket *string, dc string, objectCleanupRepo *repo.ObjectCleanupRepository, req *copyS3ObjectReq) error {
	copySource := fmt.Sprintf("%s/%s", *bucket, req.SourceS3Object.ObjectKey)
	start := time.Now()
	var err error
	if req.SourceS3Object.FileSize <= maxSingleCopySize {
		err = copyS3ObjectSingle(ctx, s3Client, bucket, copySource, req.DestObjectKey)
	} else {
		err = copyS3ObjectMultipart(ctx, s3Client, bucket, dc, objectCleanupRepo, copySource, req)
	}
	if err != nil {
		return fmt.Errorf("failed to copy (%s) from %s to %s: %w", req.SourceS3Object.Type, copySource, req.DestObjectKey, err)
	}
	logrus.WithField("duration", time.Since(start)).WithField("size", req.SourceS3Object.FileSize).Infof("copied (%s) from %s to %s", req.SourceS3Object.Type, copySource, req.DestObjectKey)
	return nil
}

func copyS3ObjectSingle(ctx context.Context, s3Client *s3.S3, bucket *string, copySource string, destObjectKey string) error {
	copyInput := &s3.CopyObjectInput{
		Bucket:     bucket,
		CopySource: &copySource,
		Key:        &destObjectKey,
	}
	_, err := s3Client.CopyObjectWithContext(ctx, copyInput)
	return err
}

func copyS3ObjectMultipart(ctx context.Context, s3Client *s3.S3, bucket *string, dc string, objectCleanupRepo *repo.ObjectCleanupRepository, copySource string, req *copyS3ObjectReq) (err error) {
	created, err := s3Client.CreateMultipartUploadWithContext(ctx, &s3.CreateMultipartUploadInput{
		Bucket: bucket,
		Key:    &req.DestObjectKey,
	})
	if err != nil {
		return fmt.Errorf("failed to create multipart upload: %w", err)
	}
	uploadID := aws.StringValue(created.UploadId)
	if uploadID == "" {
		return errors.New("multipart upload returned an empty upload ID")
	}
	defer func() {
		if err == nil {
			return
		}
		abortCtx, cancel := context.WithTimeout(context.Background(), multipartAbortTimeout)
		defer cancel()
		_, abortErr := s3Client.AbortMultipartUploadWithContext(abortCtx, &s3.AbortMultipartUploadInput{
			Bucket:   bucket,
			Key:      &req.DestObjectKey,
			UploadId: &uploadID,
		})
		if abortErr != nil {
			err = errors.Join(err, fmt.Errorf("failed to abort multipart copy: %w", abortErr))
		}
	}()

	if err = objectCleanupRepo.MarkTempObjectMultipart(ctx, req.DestObjectKey, uploadID, dc); err != nil {
		return fmt.Errorf("failed to record multipart copy: %w", err)
	}

	parts := make([]*s3.CompletedPart, 0, (req.SourceS3Object.FileSize+multipartCopyPartSize-1)/multipartCopyPartSize)
	for start := int64(0); start < req.SourceS3Object.FileSize; start += multipartCopyPartSize {
		end := min(start+multipartCopyPartSize-1, req.SourceS3Object.FileSize-1)
		partNumber := int64(len(parts) + 1)
		copied, copyErr := s3Client.UploadPartCopyWithContext(ctx, &s3.UploadPartCopyInput{
			Bucket:          bucket,
			CopySource:      &copySource,
			CopySourceRange: aws.String(fmt.Sprintf("bytes=%d-%d", start, end)),
			Key:             &req.DestObjectKey,
			PartNumber:      &partNumber,
			UploadId:        &uploadID,
		})
		if copyErr != nil {
			return fmt.Errorf("failed to copy part %d: %w", partNumber, copyErr)
		}
		if copied.CopyPartResult == nil || copied.CopyPartResult.ETag == nil {
			return fmt.Errorf("multipart copy part %d returned no ETag", partNumber)
		}
		parts = append(parts, &s3.CompletedPart{ETag: copied.CopyPartResult.ETag, PartNumber: &partNumber})
	}

	_, err = s3Client.CompleteMultipartUploadWithContext(ctx, &s3.CompleteMultipartUploadInput{
		Bucket:   bucket,
		Key:      &req.DestObjectKey,
		UploadId: &uploadID,
		MultipartUpload: &s3.CompletedMultipartUpload{
			Parts: parts,
		},
	})
	if err != nil {
		return fmt.Errorf("failed to complete multipart upload: %w", err)
	}
	return nil
}
