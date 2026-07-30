package filedata

import (
	"fmt"

	"github.com/ente/museum/ente"
)

/*
We store three types of derived data from a file, whose information is stored in the file_data table.
Each derived data can have multiple objects, and each object is stored in the S3 bucket.
1) MLData: This is the derived data from the file that is used for machine learning purposes.There's only
one object for S3FileMetadata type.
2) PreviewVideo: This is the derived data from the file that is used for previewing the video. This contains two objects.
2.1) One object of type S3FileMetadata that contains the encrypted HLS playlist.
2.2) Second object contains the encrypted video. The objectKey for this object is derived via ObjectKey function. The OG size column in the file_data
contains sum of S3Metadata object size and the video object size. The object size is stored in the ObjectSize column.

3) PreviewImage: This is the derived data from the file that is used for previewing the image. This just contain one object.
The objectKey for this object is derived via ObjectKey function. We also store the nonce of the object in the ObjectNonce column.
ObjectNonce is not stored for PreviewVideo type as HLS playlist contains a random key, that's only used once to encrypt the video with default nonce.
*/

type Entity struct {
	FileID           int64           `json:"fileID"`
	Type             ente.ObjectType `json:"type"`
	EncryptedData    string          `json:"encryptedData"`
	DecryptionHeader string          `json:"decryptionHeader"`
	UpdatedAt        int64           `json:"updatedAt"`
}

type FDDiffRequest struct {
	LastUpdatedAt *int64 `form:"lastUpdatedAt"`
}

type FDStatus struct {
	FileID      int64           `json:"fileID" binding:"required"`
	UserID      int64           `json:"userID" binding:"required"`
	Type        ente.ObjectType `json:"type" binding:"required"`
	IsDeleted   bool            `json:"isDeleted" binding:"required"`
	ObjectID    *string         `json:"objectID"`
	ObjectNonce *string         `json:"objectNonce"`
	Size        int64           `json:"size"  binding:"required"`
	UpdatedAt   int64           `json:"updatedAt"  binding:"required"`
}

// GetFilesData should only be used for getting the preview video playlist and derived metadata.
type GetFilesData struct {
	FileIDs []int64         `json:"fileIDs" binding:"required"`
	Type    ente.ObjectType `json:"type" binding:"required"`
}

func (g *GetFilesData) Validate() error {
	if g.Type != ente.PreviewVideo && g.Type != ente.MlData {
		return ente.NewBadRequestWithMessage(fmt.Sprintf("unsupported object type %s", g.Type))
	}
	if len(g.FileIDs) == 0 {
		return ente.NewBadRequestWithMessage("fileIDs are required")
	}
	if len(g.FileIDs) > 200 {
		return ente.NewBadRequestWithMessage("fileIDs should be less than or equal to 200")
	}
	return nil
}

type GetFileData struct {
	FileID          int64           `form:"fileID" binding:"required"`
	Type            ente.ObjectType `form:"type" binding:"required"`
	PreferNoContent bool            `form:"preferNoContent"`
}

func (g *GetFileData) Validate() error {
	if g.Type != ente.PreviewVideo && g.Type != ente.MlData {
		return ente.NewBadRequestWithMessage(fmt.Sprintf("unsupported object type %s", g.Type))
	}
	return nil
}

type GetFilesDataResponse struct {
	Data                []Entity `json:"data"`
	PendingIndexFileIDs []int64  `json:"pendingIndexFileIDs"`
	ErrFileIDs          []int64  `json:"errFileIDs"`
}

// S3FileMetadata stuck represents the metadata that is stored in the S3 bucket for non-file type metadata
// that is stored in the S3 bucket.
type S3FileMetadata struct {
	Version          int    `json:"v"`
	EncryptedData    string `json:"encryptedData"`
	DecryptionHeader string `json:"header"`
	Client           string `json:"client"`
}

type GetPreviewURLRequest struct {
	FileID int64           `form:"fileID" binding:"required"`
	Type   ente.ObjectType `form:"type" binding:"required"`
	Suffix *string         `form:"suffix"`
}

func (g *GetPreviewURLRequest) Validate() error {
	if g.Type != ente.PreviewVideo && g.Type != ente.PreviewImage {
		return ente.NewBadRequestWithMessage(fmt.Sprintf("unsupported object type %s", g.Type))
	}
	return nil
}

type PreviewUploadUrlRequest struct {
	FileID      int64           `form:"fileID" binding:"required"`
	Type        ente.ObjectType `form:"type" binding:"required"`
	IsMultiPart bool            `form:"isMultiPart"`
	Count       *int64          `form:"count"`
}

type PreviewUploadUrl struct {
	ObjectID    string    `json:"objectID" binding:"required"`
	Url         *string   `json:"url,omitempty"`
	PartURLs    *[]string `json:"partURLs,omitempty"`
	CompleteURL *string   `json:"completeURL,omitempty"`
}

func (g *PreviewUploadUrlRequest) Validate() error {
	if g.Type != ente.PreviewVideo && g.Type != ente.PreviewImage {
		return ente.NewBadRequestWithMessage(fmt.Sprintf("unsupported object type %s", g.Type))
	}
	if !g.IsMultiPart {
		return nil
	}
	if g.Count == nil {
		return ente.NewBadRequestWithMessage("count is required for multipart upload")
	} else if *g.Count <= 0 || *g.Count > 10000 {
		return ente.NewBadRequestWithMessage("invalid count, should be between 1 and 10000")
	}

	return nil
}

// Row represents the data that is stored in the file_data table.
type Row struct {
	FileID int64
	UserID int64
	Type   ente.ObjectType
	// If a file type has multiple objects, then the size is the sum of all the objects.
	Size         int64
	LatestBucket string
	ObjectID     *string
	// For HLS video object, there's no object nonce, all relevant data
	// is stored in the metadata object that primarily contains the playlist.
	ObjectNonce *string
	// Size of the object that is stored in the S3 bucket.
	// In case of HLS video, this points to the size of the encrypted video.
	// The playlist size can be calculated by the size - objectSize.
	ObjectSize        *int64
	ReplicatedBuckets []string
	DeleteFromBuckets []string
	InflightReplicas  []string
	PendingSync       bool
	IsDeleted         bool
	SyncLockedTill    int64
	CreatedAt         int64
	UpdatedAt         int64
}

// S3FileMetadataObjectKey returns the object key for the metadata stored in the S3 bucket.
func (r *Row) S3FileMetadataObjectKey() string {
	if r.Type == ente.MlData || r.Type == ente.PreviewVideo {
		return ObjectMetadataKey(r.FileID, r.UserID, r.Type, r.ObjectID)
	}
	panic(fmt.Sprintf("S3FileMetadata should not be written for %s type", r.Type))
}

// GetS3FileObjectKey returns the object key for the file data stored in the S3 bucket.
func (r *Row) GetS3FileObjectKey() string {
	if r.Type == ente.PreviewVideo || r.Type == ente.PreviewImage {
		return ObjectKey(r.FileID, r.UserID, r.Type, r.ObjectID)
	}
	panic(fmt.Sprintf("unsupported object type %s", r.Type))
}
