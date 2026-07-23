package ente

import (
	"database/sql/driver"
	"encoding/json"

	"github.com/ente/stacktrace"
)

// File represents an encrypted file in the system
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
	// IsDeleted is True when the file ID is removed from the  CollectionID
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
	// IsDeleted is True when the file ID is removed from the  CollectionID
	IsDeleted          bool           `json:"isDeleted"`
	UpdationTime       int64          `json:"updationTime"`
	MagicMetadata      *MagicMetadata `json:"magicMetadata,omitempty"`
	PubicMagicMetadata *MagicMetadata `json:"pubMagicMetadata,omitempty"`
}

// FileInfo has information about storage used by the file & it's metadata(future)
type FileInfo struct {
	FileSize      int64 `json:"fileSize,omitempty"`
	ThumbnailSize int64 `json:"thumbSize,omitempty"`
}

// Value implements the driver.Valuer interface. This method
// simply returns the JSON-encoded representation of the struct.
func (fi FileInfo) Value() (driver.Value, error) {
	return json.Marshal(fi)
}

// Scan implements the sql.Scanner interface. This method
// simply decodes a JSON-encoded value into the struct fields.
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

// UpdateFileResponse represents a response to the UpdateFileRequest
type UpdateFileResponse struct {
	ID           int64 `json:"id" binding:"required"`
	UpdationTime int64 `json:"updationTime" binding:"required"`
}

// FileIDsRequest represents a request where we just pass fileIDs as payload
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
	OwnerID    int64              // ownerID will be set internally via auth header
	TrashItems []TrashItemRequest `json:"items" binding:"required"`
}

// TrashItemRequest represents the request payload for deleting one file
type TrashItemRequest struct {
	FileID int64 `json:"fileID" binding:"required"`
	// collectionID belonging to same owner
	CollectionID int64 `json:"collectionID" binding:"required"`
}

// GetSizeRequest represents a request to get the size of files
type GetSizeRequest struct {
	FileIDs []int64 `json:"fileIDs" binding:"required"`
}

// FileAttributes represents a file item
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
	Count int `json:"count,omitempty" binding:"required"`
	// Data represents the encrypted blob for jsonEncoded attributes using file key.
	Data string `json:"data,omitempty" binding:"required"`
	// Header used for decrypting the encrypted attr on the client.
	Header string `json:"header,omitempty" binding:"required"`
}

// Value implements the driver.Valuer interface. This method
// simply returns the JSON-encoded representation of the struct.
func (mmd MagicMetadata) Value() (driver.Value, error) {
	return json.Marshal(mmd)
}

// Scan implements the sql.Scanner interface. This method
// simply decodes a JSON-encoded value into the struct fields.
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

// UpdateMagicMetadata payload for updating magic metadata for single file
type UpdateMagicMetadata struct {
	ID            int64         `json:"id" binding:"required"`
	MagicMetadata MagicMetadata `json:"magicMetadata" binding:"required"`
}

// UpdateMultipleMagicMetadataRequest request payload for updating magic metadata for list of files
type UpdateMultipleMagicMetadataRequest struct {
	MetadataList []UpdateMagicMetadata `json:"metadataList" binding:"required"`
	SkipVersion  *bool                 `json:"skipVersion"`
}

// UploadURL represents the upload url for a specific object
type UploadURL struct {
	ObjectKey string `json:"objectKey"`
	URL       string `json:"url"`
}

// UploadURLRequest represents the inputs necessary to mint a single upload URL
type UploadURLRequest struct {
	ContentLength int64  `json:"contentLength" binding:"required"`
	ContentMD5    string `json:"contentMD5" binding:"required"`
}

// MultipartUploadURLs represents the part upload url for a specific object
type MultipartUploadURLs struct {
	ObjectKey   string   `json:"objectKey"`
	PartURLs    []string `json:"partURLs"`
	CompleteURL string   `json:"completeURL"`
}

// MultipartUploadURLRequest encapsulates the metadata needed to mint a multipart upload URL set
type MultipartUploadURLRequest struct {
	ContentLength int64    `json:"contentLength" binding:"required"`
	PartLength    int64    `json:"partLength" binding:"required"`
	PartMD5s      []string `json:"partMd5s" binding:"required"`
}

type ObjectType string

const (
	FILE         ObjectType = "file"
	THUMBNAIL    ObjectType = "thumbnail"
	PreviewImage ObjectType = "img_preview"
	PreviewVideo ObjectType = "vid_preview"
	MlData       ObjectType = "mldata"
)

// S3ObjectKey represents the s3 object key and corresponding fileID for it
type S3ObjectKey struct {
	FileID    int64
	ObjectKey string
	FileSize  int64
	Type      ObjectType
}

// ObjectCopies represents a row from the object_copies table.
//
// It contains information about which replicas a given object key should be and
// has been replicated to.
type ObjectCopies struct {
	ObjectKey  string
	WantB2     bool
	B2         *int64
	WantWasabi bool
	Wasabi     *int64
	WantSCW    bool
	SCW        *int64
}

// ObjectState represents details about an object that are needed for
// pre-flights checks during replication.
//
// This information is obtained by joining various tables.
type ObjectState struct {
	// true if the file corresponding to this object has been deleted (or cannot
	// be found)
	IsFileDeleted bool
	// true if the owner of the file corresponding to this object has deleted
	// their account (or cannot be found).
	IsUserDeleted bool
	// Size of the object, in bytes.
	Size int64
}

// TempObject represents a entry in tempObjects table
type TempObject struct {
	ObjectKey   string
	IsMultipart bool
	UploadID    string
	BucketId    string
}

// DuplicateFiles represents duplicate files
type DuplicateFiles struct {
	FileIDs []int64 `json:"fileIDs"`
	Size    int64   `json:"size"`
}

type UpdateThumbnailRequest struct {
	FileID    int64          `json:"fileID" binding:"required"`
	Thumbnail FileAttributes `json:"thumbnail" binding:"required"`
}
