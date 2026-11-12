package file_copy

import (
	"context"
	"fmt"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/controller/collections"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/network"
	"github.com/ente/museum/pkg/utils/s3config"
	enteTime "github.com/ente/museum/pkg/utils/time"
	"github.com/gin-contrib/requestid"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/sirupsen/logrus"
	"golang.org/x/sync/errgroup"
	"slices"
	"strconv"
	"sync"
	"time"
)

type FileCopyController struct {
	S3Config       *s3config.S3Config
	FileController *controller.FileController
	FileRepo       *repo.FileRepository
	CollectionCtrl *collections.CollectionController
	ObjectRepo     *repo.ObjectRepository
}

type copyS3ObjectReq struct {
	SourceS3Object ente.S3ObjectKey
	Destination    ente.TempObject
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
	newFileAttributes.ObjectKey = fci.FileCopyReq.Destination.ObjectKey
	newThumbAttributes := fci.SourceFile.Thumbnail
	newThumbAttributes.ObjectKey = fci.ThumbCopyReq.Destination.ObjectKey
	return ente.File{
		OwnerID:             ownedID,
		CollectionID:        fci.DestCollectionID,
		EncryptedKey:        fci.EncryptedFileKey,
		KeyDecryptionNonce:  fci.EncryptedFileKeyNonce,
		File:                newFileAttributes,
		Thumbnail:           newThumbAttributes,
		Metadata:            fci.SourceFile.Metadata,
		PublicMagicMetadata: fci.SourceFile.PublicMagicMetadata,
		UpdationTime:        enteTime.Microseconds(),
		IsDeleted:           false,
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

	if err := fc.FileController.ValidateUploadEligibility(c, userID, app); err != nil {
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
	for _, s3Obj := range s3ObjectsToCopy {
		bucket, err := fc.copyBucket(s3Obj.DataCenters)
		if err != nil {
			return nil, fmt.Errorf("cannot copy object %s: %w", s3Obj.ObjectKey, err)
		}
		copyReq := &copyS3ObjectReq{
			SourceS3Object: s3Obj.S3ObjectKey,
			Destination: ente.TempObject{
				ObjectKey: strconv.FormatInt(userID, 10) + "/" + uuid.NewString(),
				BucketId:  bucket,
				UserID:    userID,
				App:       app,
				Purpose:   "file_upload",
				Client:    network.GetClientInfo(c),
			},
		}
		if s3Obj.Type == ente.FILE {
			fileOGS3Object[s3Obj.FileID] = copyReq
		} else if s3Obj.Type == ente.THUMBNAIL {
			fileThumbS3Object[s3Obj.FileID] = copyReq
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
	g := new(errgroup.Group)
	g.Go(func() error {
		return fc.copyS3Object(c.Request.Context(), fcInternal.FileCopyReq)
	})
	g.Go(func() error {
		return fc.copyS3Object(c.Request.Context(), fcInternal.ThumbCopyReq)
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

func (fc *FileCopyController) copyBucket(dataCenters []string) (string, error) {
	for _, dc := range []string{fc.S3Config.GetHotDataCenter(), fc.S3Config.GetSecondaryHotDataCenter()} {
		if dc != fc.S3Config.GetHotBackblazeDC() && dc != fc.S3Config.GetHotWasabiDC() {
			continue
		}
		if slices.Contains(dataCenters, dc) {
			return dc, nil
		}
	}
	return "", fmt.Errorf("no recorded hot storage copy")
}

func (fc *FileCopyController) copyS3Object(ctx context.Context, req *copyS3ObjectReq) error {
	if err := fc.FileController.ObjectCleanupCtrl.AddTempObject(req.Destination); err != nil {
		return err
	}
	s3Client := fc.S3Config.GetS3Client(req.Destination.BucketId)
	bucket := fc.S3Config.GetBucket(req.Destination.BucketId)
	copySource := fmt.Sprintf("%s/%s", *bucket, req.SourceS3Object.ObjectKey)
	copyInput := &s3.CopyObjectInput{
		Bucket:     bucket,
		CopySource: &copySource,
		Key:        &req.Destination.ObjectKey,
	}
	start := time.Now()
	_, err := s3Client.CopyObjectWithContext(ctx, copyInput)
	elapsed := time.Since(start)
	if err != nil {
		return fmt.Errorf("failed to copy (%s) from %s to %s: %w", req.SourceS3Object.Type, copySource, req.Destination.ObjectKey, err)
	}
	logrus.WithField("duration", elapsed).WithField("size", req.SourceS3Object.FileSize).Infof("copied (%s) from %s to %s", req.SourceS3Object.Type, copySource, req.Destination.ObjectKey)
	return nil
}
