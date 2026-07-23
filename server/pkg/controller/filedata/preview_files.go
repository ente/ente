package filedata

import (
	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/filedata"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

func (c *Controller) GetPreviewUrl(ctx *gin.Context, actorUser int64, request filedata.GetPreviewURLRequest) (*string, error) {
	if err := request.Validate(); err != nil {
		return nil, err
	}
	if err := c._checkMetadataReadOrWritePerm(ctx, actorUser, []int64{request.FileID}); err != nil {
		return nil, err
	}
	data, err := c.Repo.GetFilesData(ctx, request.Type, []int64{request.FileID})
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if len(data) == 0 || data[0].IsDeleted {
		return nil, stacktrace.Propagate(&ente.ErrNotFoundError, "")
	}
	enteUrl, err := c.signedUrlGet(data[0].LatestBucket, data[0].GetS3FileObjectKey())
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &enteUrl.URL, nil
}

func (c *Controller) PreviewUploadURL(ctx *gin.Context, request filedata.PreviewUploadUrlRequest) (*filedata.PreviewUploadUrl, error) {
	if err := request.Validate(); err != nil {
		return nil, err
	}
	actorUser := auth.GetUserID(ctx.Request.Header)
	if err := c._checkPreviewWritePerm(ctx, request.FileID, actorUser); err != nil {
		return nil, err
	}
	fileOwnerID, err := c.FileRepo.GetOwnerID(request.FileID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	id := filedata.NewUploadID(request.Type)
	// note: instead of the final url, give a temp url for upload purpose.
	objectKey := filedata.ObjectKey(request.FileID, fileOwnerID, request.Type, &id)
	bucketID := c.S3Config.GetBucketID(request.Type)
	if request.IsMultiPart {
		multiPartUploadURLs, err2 := c.getMultiPartUploadURL(bucketID, objectKey, request.Count)
		if err2 != nil {
			return nil, stacktrace.Propagate(err2, "")
		}
		return &filedata.PreviewUploadUrl{
			ObjectID:    id,
			PartURLs:    &multiPartUploadURLs.PartURLs,
			CompleteURL: &multiPartUploadURLs.CompleteURL,
		}, nil
	}
	enteUrl, err := c.getUploadURL(bucketID, objectKey)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &filedata.PreviewUploadUrl{
		ObjectID: id,
		Url:      &enteUrl.URL,
	}, nil
}
