package ente

import (
	"database/sql/driver"
	"encoding/json"

	"github.com/ente/stacktrace"
)

type File struct {
	ID                 int64          `json:"id"`
	OwnerID            int64          `json:"ownerID"`
	CollectionID       int64          `json:"collectionID"`
	CollectionOwnerID  *int64         `json:"collectionOwnerID"`
	CollectionAddedAt  *int64         `json:"collectionAddedAt,omitempty"`
	EncryptedKey       string         `json:"encryptedKey"`
	KeyDecryptionNonce string         `json:"keyDecryptionNonce"`
	File               FileAttributes `json:"file" binding:"required"`
	Thumbnail          FileAttributes `json:"thumbnail" binding:"required"`
	Metadata           FileAttributes `json:"metadata" binding:"required"`
	// True when the file was removed from this collection.
	IsDeleted          bool           `json:"isDeleted"`
	UpdationTime       int64          `json:"updationTime"`
	MagicMetadata      *MagicMetadata `json:"magicMetadata,omitempty"`
	PubicMagicMetadata *MagicMetadata `json:"pubMagicMetadata,omitempty"`
	Info               *FileInfo      `json:"info,omitempty"`
	// Action and ActionUser are optionally set to drive client-side behavior during diffs
	Action       *string `json:"action,omitempty"`
	ActionUserID *int64  `json:"actionUser,omitempty"`
}

type MetaFile struct {
	ID                 int64          `json:"id"`
	OwnerID            int64          `json:"ownerID"`
	CollectionID       int64          `json:"collectionID"`
	EncryptedKey       string         `json:"encryptedKey"`
	KeyDecryptionNonce string         `json:"keyDecryptionNonce"`
	Metadata           FileAttributes `json:"metadata" binding:"required"`
	// True when the file was removed from this collection.
	IsDeleted          bool           `json:"isDeleted"`
	UpdationTime       int64          `json:"updationTime"`
	MagicMetadata      *MagicMetadata `json:"magicMetadata,omitempty"`
	PubicMagicMetadata *MagicMetadata `json:"pubMagicMetadata,omitempty"`
}

type FileInfo struct {
	FileSize      int64 `json:"fileSize,omitempty"`
	ThumbnailSize int64 `json:"thumbSize,omitempty"`
}

func (fi FileInfo) Value() (driver.Value, error) {
	return json.Marshal(fi)
}

func (fi *FileInfo) Scan(value interface{}) error {
	if value == nil {
		return nil
	}
	b, ok := value.([]byte)
	if !ok {
		return stacktrace.NewError("type assertion to []byte failed")
	}
	return json.Unmarshal(b, &fi)
}

type UpdateFileResponse struct {
	ID           int64 `json:"id" binding:"required"`
	UpdationTime int64 `json:"updationTime" binding:"required"`
}

type FileIDsRequest struct {
	FileIDs []int64 `json:"fileIDs" binding:"required"`
}

type FileInfoResponse struct {
	ID       int64    `json:"id"`
	FileInfo FileInfo `json:"fileInfo"`
}
type FilesInfoResponse struct {
	FilesInfo []*FileInfoResponse `json:"filesInfo"`
}

type TrashRequest struct {
	OwnerID    int64              // Set from the authenticated user, not the request body.
	TrashItems []TrashItemRequest `json:"items" binding:"required"`
}

type TrashItemRequest struct {
	FileID       int64 `json:"fileID" binding:"required"`
	CollectionID int64 `json:"collectionID" binding:"required"`
}

type GetSizeRequest struct {
	FileIDs []int64 `json:"fileIDs" binding:"required"`
}

type FileAttributes struct {
	ObjectKey        string `json:"objectKey,omitempty"`
	EncryptedData    string `json:"encryptedData,omitempty"`
	DecryptionHeader string `json:"decryptionHeader" binding:"required"`
	Size             int64  `json:"size"`
}

type MagicMetadata struct {
	Version int `json:"version,omitempty" binding:"required"`
	// Count indicates number of keys in the json presentation of magic attributes.
	// On edit/update, this number should be >= previous version.
	Count  int    `json:"count,omitempty" binding:"required"`
	Data   string `json:"data,omitempty" binding:"required"`
	Header string `json:"header,omitempty" binding:"required"`
}

func (mmd MagicMetadata) Value() (driver.Value, error) {
	return json.Marshal(mmd)
}

func (mmd *MagicMetadata) Scan(value interface{}) error {
	if value == nil {
		return nil
	}
	b, ok := value.([]byte)
	if !ok {
		return stacktrace.NewError("type assertion to []byte failed")
	}
	return json.Unmarshal(b, &mmd)
}

type UpdateMagicMetadata struct {
	ID            int64         `json:"id" binding:"required"`
	MagicMetadata MagicMetadata `json:"magicMetadata" binding:"required"`
}

type UpdateMultipleMagicMetadataRequest struct {
	MetadataList []UpdateMagicMetadata `json:"metadataList" binding:"required"`
	SkipVersion  *bool                 `json:"skipVersion"`
}

type UploadURL struct {
	ObjectKey string `json:"objectKey"`
	URL       string `json:"url"`
}

type UploadURLRequest struct {
	ContentLength int64  `json:"contentLength" binding:"required"`
	ContentMD5    string `json:"contentMD5" binding:"required"`
}

type MultipartUploadURLs struct {
	ObjectKey   string   `json:"objectKey"`
	PartURLs    []string `json:"partURLs"`
	CompleteURL string   `json:"completeURL"`
}

type MultipartUploadURLRequest struct {
	ContentLength int64    `json:"contentLength" binding:"required"`
	PartLength    int64    `json:"partLength" binding:"required"`
	PartMD5s      []string `json:"partMd5s"`
}

type ObjectType string

const (
	FILE         ObjectType = "file"
	THUMBNAIL    ObjectType = "thumbnail"
	PreviewImage ObjectType = "img_preview"
	PreviewVideo ObjectType = "vid_preview"
	MlData       ObjectType = "mldata"
)

type S3ObjectKey struct {
	FileID    int64
	ObjectKey string
	FileSize  int64
	Type      ObjectType
}

type ObjectCopies struct {
	ObjectKey  string
	WantB2     bool
	B2         *int64
	WantWasabi bool
	Wasabi     *int64
	WantSCW    bool
	SCW        *int64
}

type ObjectState struct {
	IsFileDeleted bool
	IsUserDeleted bool
	Size          int64
}

type TempObject struct {
	ObjectKey   string
	IsMultipart bool
	UploadID    string
	BucketId    string
}

type DuplicateFiles struct {
	FileIDs []int64 `json:"fileIDs"`
	Size    int64   `json:"size"`
}

type UpdateThumbnailRequest struct {
	FileID    int64          `json:"fileID" binding:"required"`
	Thumbnail FileAttributes `json:"thumbnail" binding:"required"`
}
