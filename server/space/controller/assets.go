package controller

import (
	"context"
	"crypto/md5"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/base"
	timeutil "github.com/ente/museum/pkg/utils/time"
	"github.com/ente/museum/space/models"
	spacerepo "github.com/ente/museum/space/repo"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

const (
	maxPostUploadBytes     int64 = 5 * 1024 * 1024
	maxAvatarUploadBytes   int64 = 2 * 1024 * 1024
	maxCoverUploadBytes    int64 = 2 * 1024 * 1024
	uploadURLExpiry              = spacerepo.SpaceUploadURLExpiry
	uploadTempObjectExpiry       = spacerepo.SpaceUploadCleanupDelay
	uploadPurposePost            = spacerepo.TempObjectPurposePost
	uploadPurposeAvatar          = spacerepo.TempObjectPurposeAvatar
	uploadPurposeCover           = spacerepo.TempObjectPurposeCover
	uploadContentType            = "application/octet-stream"
)

type AssetsController struct {
	AssetsRepo *spacerepo.AssetsRepository
	SpacesRepo *spacerepo.SpacesRepository
	auth       authDeps
}

func (c *AssetsController) PresignUpload(ctx context.Context, space *spacerepo.SpaceRecord, req models.PresignUploadRequest) (*models.PresignUploadResponse, error) {
	purpose := uploadPurposePost
	if req.Purpose != nil && strings.TrimSpace(*req.Purpose) != "" {
		purpose = strings.TrimSpace(*req.Purpose)
	}
	maxUploadBytes, err := maxUploadBytesForPurpose(purpose)
	if err != nil {
		return nil, err
	}
	if req.Size <= 0 || req.Size > maxUploadBytes {
		return nil, ente.NewBadRequestWithMessage(fmt.Sprintf("size must be between 1 and %d bytes", maxUploadBytes))
	}
	contentMD5, err := normalizeContentMD5(req.ContentMD5)
	if err != nil {
		return nil, err
	}
	bucketID, err := resolveSpaceAssetsBucketID(c.AssetsRepo.S3Config)
	if err != nil {
		return nil, err
	}
	bucket := c.AssetsRepo.S3Config.GetBucket(bucketID)
	s3Client := c.AssetsRepo.S3Config.GetS3Client(bucketID)

	keyPrefix := fmt.Sprintf("space/%s/posts", space.SpaceID)
	if purpose == uploadPurposeAvatar {
		keyPrefix = fmt.Sprintf("space/%s/avatar", space.SpaceID)
	}
	if purpose == uploadPurposeCover {
		keyPrefix = fmt.Sprintf("space/%s/cover", space.SpaceID)
	}
	objectKey := fmt.Sprintf("%s/%s", keyPrefix, base.MustNewID("wo"))
	err = c.AssetsRepo.ReserveTempObject(ctx, spacerepo.SpaceTempObjectRecord{
		ObjectKey:    objectKey,
		SpaceID:      sql.NullString{String: space.SpaceID, Valid: true},
		Purpose:      purpose,
		BucketID:     bucketID,
		ExpectedSize: req.Size,
		ExpiresAt:    timeutil.Microseconds() + int64(uploadTempObjectExpiry/time.Microsecond),
	})
	if errors.Is(err, spacerepo.ErrSpaceUploadLimitReached) {
		return nil, newSpaceUploadLimitError()
	}
	if err != nil {
		return nil, err
	}
	input := &s3.PutObjectInput{
		Bucket:        bucket,
		Key:           aws.String(objectKey),
		ContentLength: aws.Int64(req.Size),
		ContentMD5:    aws.String(contentMD5),
		ContentType:   aws.String(uploadContentType),
	}
	putReq, _ := s3Client.PutObjectRequest(input)
	url, err := putReq.Presign(uploadURLExpiry)
	if err != nil {
		if cleanupErr := c.AssetsRepo.RemoveTempObject(ctx, objectKey); cleanupErr != nil {
			return nil, stacktrace.Propagate(cleanupErr, "failed to release space upload reservation")
		}
		return nil, err
	}
	return &models.PresignUploadResponse{
		URL:       url,
		Method:    "PUT",
		Headers:   map[string]string{"Content-Type": uploadContentType, "Content-MD5": contentMD5},
		ObjectKey: objectKey,
		ExpiresIn: int(uploadURLExpiry.Seconds()),
	}, nil
}

func newSpaceUploadLimitError() *ente.ApiError {
	return &ente.ApiError{
		Code:           ente.ErrorCode("SPACE_UPLOAD_LIMIT_REACHED"),
		Message:        "too many unfinished space uploads",
		HttpStatusCode: http.StatusTooManyRequests,
	}
}

func normalizeContentMD5(value string) (string, error) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return "", ente.NewBadRequestWithMessage("contentMD5 is required")
	}
	decoded, err := base64.StdEncoding.DecodeString(trimmed)
	if err != nil || len(decoded) != md5.Size {
		hexDecoded, hexErr := hex.DecodeString(trimmed)
		if hexErr == nil {
			decoded = hexDecoded
		} else if err != nil {
			return "", ente.NewBadRequestWithMessage("contentMD5 must be base64 or hex encoded")
		}
	}
	if len(decoded) != md5.Size {
		return "", ente.NewBadRequestWithMessage("contentMD5 must be exactly 16 bytes")
	}
	return base64.StdEncoding.EncodeToString(decoded), nil
}

func maxUploadBytesForPurpose(purpose string) (int64, error) {
	switch purpose {
	case uploadPurposePost:
		return maxPostUploadBytes, nil
	case uploadPurposeAvatar:
		return maxAvatarUploadBytes, nil
	case uploadPurposeCover:
		return maxCoverUploadBytes, nil
	default:
		return 0, ente.NewBadRequestWithMessage("invalid upload purpose")
	}
}

func verifyStagedUpload(ctx context.Context, assetsRepo *spacerepo.AssetsRepository, objectKey, purpose string, spaceID *string) (*spacerepo.SpaceTempObjectRecord, error) {
	objectKey = strings.TrimSpace(objectKey)
	if objectKey == "" {
		return nil, ente.NewBadRequestWithMessage("objectKey is required")
	}
	rec, err := assetsRepo.GetTempObject(ctx, objectKey, purpose, spaceID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ente.NewBadRequestWithMessage("staged space upload not found")
		}
		return nil, err
	}
	if rec.ExpiresAt <= timeutil.Microseconds() {
		return nil, ente.NewBadRequestWithMessage("staged space upload expired")
	}
	s3Client := assetsRepo.S3Config.GetS3Client(rec.BucketID)
	head, err := s3Client.HeadObject(&s3.HeadObjectInput{
		Bucket: assetsRepo.S3Config.GetBucket(rec.BucketID),
		Key:    aws.String(rec.ObjectKey),
	})
	if err != nil {
		return nil, err
	}
	if head.ContentLength == nil || *head.ContentLength != rec.ExpectedSize {
		return nil, ente.NewBadRequestWithMessage("space upload size mismatch")
	}
	return rec, nil
}

func (c *AssetsController) Redirect(ctx *gin.Context, req models.AssetRedirectRequest) (*models.AssetDownloadResponse, error) {
	viewer, err := c.auth.resolveViewer(ctx, req.ViewerSpaceID)
	if err != nil {
		return nil, err
	}
	space, err := c.SpacesRepo.GetSpaceByID(ctx, req.SpaceID)
	if err != nil {
		return nil, err
	}
	if err := c.auth.canViewSpace(ctx, viewer, space); err != nil {
		return nil, err
	}
	objectKey := strings.TrimSpace(req.ObjectKey)
	var bucketID string
	if objectKey == "" {
		assetType := strings.TrimSpace(req.AssetType)
		objectID := strings.TrimSpace(req.ObjectID)
		if !spacerepo.IsProfileAssetType(assetType) || !spacerepo.IsProfileAssetObjectID(objectID) {
			return nil, ente.NewBadRequestWithMessage("objectKey or assetType and objectID are required")
		}
		objectKey = spacerepo.ProfileAssetObjectKey(space.SpaceID, assetType, objectID)
		bucketID, err = c.AssetsRepo.GetProfileAssetBucketID(ctx, space.SpaceID, assetType, objectID)
	} else {
		bucketID, err = c.AssetsRepo.GetAssetBucketID(ctx, space.SpaceID, objectKey)
	}
	if err != nil {
		if !errors.Is(err, sql.ErrNoRows) {
			return nil, err
		}
		return nil, ente.ErrNotFound
	}
	bucket := c.AssetsRepo.S3Config.GetBucket(bucketID)
	s3Client := c.AssetsRepo.S3Config.GetS3Client(bucketID)
	getReq, _ := s3Client.GetObjectRequest(&s3.GetObjectInput{Bucket: bucket, Key: aws.String(objectKey)})
	url, err := getReq.Presign(uploadURLExpiry)
	if err != nil {
		return nil, err
	}
	return &models.AssetDownloadResponse{
		URL:       url,
		ExpiresIn: int(uploadURLExpiry.Seconds()),
	}, nil
}
