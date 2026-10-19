package filedata

import (
	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/filedata"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/network"
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
	id, object, err := c.previewUploadObject(ctx, request.FileID, request.Type)
	if err != nil {
		return nil, err
	}
	if request.IsMultiPart {
		multiPartUploadURLs, err2 := c.getMultiPartUploadURL(object, *request.Count, 0, nil)
		if err2 != nil {
			return nil, stacktrace.Propagate(err2, "")
		}
		return &filedata.PreviewUploadUrl{
			ObjectID:    id,
			PartURLs:    &multiPartUploadURLs.PartURLs,
			CompleteURL: &multiPartUploadURLs.CompleteURL,
		}, nil
	}
	url, err := c.getUploadURL(object)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &filedata.PreviewUploadUrl{
		ObjectID: id,
		Url:      &url,
	}, nil
}

func (c *Controller) PreviewUploadURLWithMetadata(ctx *gin.Context, request filedata.PreviewUploadRequest) (*filedata.PreviewUploadUrl, error) {
	if err := request.Validate(); err != nil {
		return nil, err
	}
	id, object, err := c.previewUploadObject(ctx, request.FileID, request.Type)
	if err != nil {
		return nil, err
	}
	object.ContentLength = &request.ContentLength
	object.ContentMD5 = &request.ContentMD5
	url, err := c.getUploadURL(object)
	if err != nil {
		return nil, err
	}
	return &filedata.PreviewUploadUrl{ObjectID: id, Url: &url}, nil
}

func (c *Controller) MultipartPreviewUploadURLWithMetadata(ctx *gin.Context, request filedata.MultipartPreviewUploadRequest) (*filedata.PreviewUploadUrl, error) {
	if err := request.Validate(); err != nil {
		return nil, err
	}
	id, object, err := c.previewUploadObject(ctx, request.FileID, request.Type)
	if err != nil {
		return nil, err
	}
	object.ContentLength = &request.ContentLength
	upload, err := c.getMultiPartUploadURL(object, int64(len(request.PartMD5s)), request.PartLength, request.PartMD5s)
	if err != nil {
		return nil, err
	}
	return &filedata.PreviewUploadUrl{
		ObjectID: id, PartURLs: &upload.PartURLs, CompleteURL: &upload.CompleteURL,
	}, nil
}

func (c *Controller) previewUploadObject(ctx *gin.Context, fileID int64, objectType ente.ObjectType) (string, ente.TempObject, error) {
	actorUser := auth.GetUserID(ctx.Request.Header)
	if err := c._checkPreviewWritePerm(ctx, fileID, actorUser); err != nil {
		return "", ente.TempObject{}, err
	}
	id := filedata.NewUploadID(objectType)
	return id, ente.TempObject{
		ObjectKey: filedata.ObjectKey(fileID, actorUser, objectType, &id),
		BucketId:  c.S3Config.GetBucketID(objectType),
		UserID:    actorUser,
		App:       auth.GetApp(ctx),
		Purpose:   string(objectType),
		Client:    network.GetClientInfo(ctx),
	}, nil
}
