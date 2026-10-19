package filedata

import (
	"fmt"

	"github.com/ente/museum/ente"
)

const maxPreviewUploadSize = int64(10 << 30)

type PreviewUploadRequest struct {
	FileID        int64           `json:"fileID" binding:"required"`
	Type          ente.ObjectType `json:"type" binding:"required"`
	ContentLength int64           `json:"contentLength" binding:"required"`
	ContentMD5    string          `json:"contentMD5" binding:"required"`
}

func (r PreviewUploadRequest) Validate() error {
	if err := validatePreviewUpload(r.FileID, r.Type, r.ContentLength); err != nil {
		return err
	}
	if r.ContentLength > ente.MaxMultipartPartSize {
		return ente.NewBadRequestWithMessage("previews larger than 5 GiB require multipart upload")
	}
	return ente.ValidateMD5(r.ContentMD5)
}

type MultipartPreviewUploadRequest struct {
	FileID        int64           `json:"fileID" binding:"required"`
	Type          ente.ObjectType `json:"type" binding:"required"`
	ContentLength int64           `json:"contentLength" binding:"required"`
	PartLength    int64           `json:"partLength" binding:"required"`
	PartMD5s      []string        `json:"partMd5s" binding:"required"`
}

func (r MultipartPreviewUploadRequest) Validate() error {
	if err := validatePreviewUpload(r.FileID, r.Type, r.ContentLength); err != nil {
		return err
	}
	if err := ente.ValidateMultipartPartLength(r.ContentLength, r.PartLength); err != nil {
		return err
	}
	partCount := (r.ContentLength-1)/r.PartLength + 1
	if int64(len(r.PartMD5s)) != partCount {
		return ente.NewBadRequestWithMessage(fmt.Sprintf("partMd5s must contain exactly %d checksums", partCount))
	}
	for _, checksum := range r.PartMD5s {
		if err := ente.ValidateMD5(checksum); err != nil {
			return err
		}
	}
	return nil
}

func validatePreviewUpload(fileID int64, objectType ente.ObjectType, contentLength int64) error {
	if fileID <= 0 {
		return ente.NewBadRequestWithMessage("fileID must be greater than 0")
	}
	if objectType != ente.PreviewVideo && objectType != ente.PreviewImage {
		return ente.NewBadRequestWithMessage(fmt.Sprintf("unsupported object type %s", objectType))
	}
	if contentLength <= 0 || contentLength > maxPreviewUploadSize {
		return ente.NewBadRequestWithMessage("contentLength must be between 1 byte and 10 GiB")
	}
	return nil
}
