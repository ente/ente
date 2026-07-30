package ente

import (
	"database/sql/driver"
	"encoding/json"

	"github.com/ente/stacktrace"
)

var ValidCollectionTypes = []string{"album", "folder", "favorites", "uncategorized"}

// Collection represents a collection
type Collection struct {
	ID                  int64                `json:"id"`
	Owner               CollectionUser       `json:"owner"`
	EncryptedKey        string               `json:"encryptedKey" binding:"required"`
	KeyDecryptionNonce  string               `json:"keyDecryptionNonce,omitempty" binding:"required"`
	Name                string               `json:"name"`
	EncryptedName       string               `json:"encryptedName"`
	NameDecryptionNonce string               `json:"nameDecryptionNonce"`
	Type                string               `json:"type" binding:"required"`
	Attributes          CollectionAttributes `json:"attributes,omitempty" binding:"required"`
	Sharees             []CollectionUser     `json:"sharees"`
	PublicURLs          []PublicURL          `json:"publicURLs"`
	UpdationTime        int64                `json:"updationTime"`
	SharedAt            *int64               `json:"sharedAt,omitempty"`
	IsDeleted           bool                 `json:"isDeleted,omitempty"`
	MagicMetadata       *MagicMetadata       `json:"magicMetadata,omitempty"`
	App                 string               `json:"app"`
	PublicMagicMetadata *MagicMetadata       `json:"pubMagicMetadata,omitempty"`
	// SharedMagicMetadata keeps the metadata of the sharees to store settings like
	// if the collection should be shown on timeline or not
	SharedMagicMetadata *MagicMetadata `json:"sharedMagicMetadata,omitempty"`
}

// AllowSharing indicates if this particular collection type can be shared
// or not
func (c *Collection) AllowSharing() bool {
	if c == nil {
		return false
	}
	if c.Type == "uncategorized" {
		return false
	}
	return true
}

// AllowDelete indicates if this particular collection type can be deleted by the user
// or not
func (c *Collection) AllowDelete() bool {
	if c == nil {
		return false
	}
	if c.Type == "favorites" || c.Type == "uncategorized" {
		return false
	}
	return true
}

// CollectionUser represents the owner of a collection
type CollectionUser struct {
	ID    int64  `json:"id"`
	Email string `json:"email"`
	// Deprecated
	Name string                    `json:"name"`
	Role CollectionParticipantRole `json:"role"`
}

// CollectionAttributes represents a collection's attribtues
type CollectionAttributes struct {
	EncryptedPath       string `json:"encryptedPath,omitempty"`
	PathDecryptionNonce string `json:"pathDecryptionNonce,omitempty"`
	Version             int    `json:"version"`
}

// Value implements the driver.Valuer interface. This method
// simply returns the JSON-encoded representation of the struct.
func (ca CollectionAttributes) Value() (driver.Value, error) {
	return json.Marshal(ca)
}

// Scan implements the sql.Scanner interface. This method
// simply decodes a JSON-encoded value into the struct fields.
func (ca *CollectionAttributes) Scan(value interface{}) error {
	b, ok := value.([]byte)
	if !ok {
		return stacktrace.NewError("type assertion to []byte failed")
	}

	return json.Unmarshal(b, &ca)
}

// AlterShareRequest represents a share/unshare request
type AlterShareRequest struct {
	CollectionID int64                      `json:"collectionID" binding:"required"`
	Email        string                     `json:"email" binding:"required"`
	EncryptedKey string                     `json:"encryptedKey"`
	Role         *CollectionParticipantRole `json:"role"`
}

type JoinCollectionViaLinkRequest struct {
	CollectionID int64  `json:"collectionID" binding:"required"`
	EncryptedKey string `json:"encryptedKey" binding:"required"`
}

// AddFilesRequest represents a request to add files to a collection
type AddFilesRequest struct {
	CollectionID int64                `json:"collectionID" binding:"required"`
	Files        []CollectionFileItem `json:"files" binding:"required"`
}

// CopyFileSyncRequest is request object for creating copy of CollectionFileItems, and those copy to the destination collection
type CopyFileSyncRequest struct {
	SrcCollectionID     int64                `json:"srcCollectionID" binding:"required"`
	DstCollection       int64                `json:"dstCollectionID" binding:"required"`
	CollectionFileItems []CollectionFileItem `json:"files" binding:"required"`
}

type CopyResponse struct {
	OldToNewFileIDMap map[int64]int64 `json:"oldToNewFileIDMap"`
}

// RemoveFilesRequest represents a request to remove files from a collection
type RemoveFilesRequest struct {
	CollectionID int64 `json:"collectionID" binding:"required"`
	// OtherFileIDs represents the files which don't belong the user trying to remove files
	FileIDs []int64 `json:"fileIDs"`
}

// RemoveFilesV3Request represents request payload for v3 version of removing files from collection
// In V3, only those files are allowed to be removed from collection which don't belong to the collection owner.
// If collection owner wants to remove files owned by them, the client should move those files to other collections
// owned by the collection user. Also, See [Collection Delete Versions] for additional context.
type RemoveFilesV3Request struct {
	CollectionID int64 `json:"collectionID" binding:"required"`
	// OtherFileIDs represents the files which don't belong the user trying to remove files
	FileIDs []int64 `json:"fileIDs"  binding:"required"`
}

// SuggestDeleteRequest represents a request to suggest deletion of files in a shared collection.
// Only collection owner or admins can suggest deletion for files owned by others (not the acting user).
type SuggestDeleteRequest struct {
	CollectionID int64   `json:"collectionID" binding:"required"`
	FileIDs      []int64 `json:"fileIDs" binding:"required"`
}

type RenameRequest struct {
	CollectionID        int64  `json:"collectionID" binding:"required"`
	EncryptedName       string `json:"encryptedName" binding:"required"`
	NameDecryptionNonce string `json:"nameDecryptionNonce" binding:"required"`
}

// UpdateCollectionMagicMetadata payload for updating magic metadata for single file
type UpdateCollectionMagicMetadata struct {
	ID            int64         `json:"id" binding:"required"`
	MagicMetadata MagicMetadata `json:"magicMetadata" binding:"required"`
}

// CollectionFileItem represents a file in an AddFilesRequest and MoveFilesRequest
type CollectionFileItem struct {
	ID                 int64  `json:"id" binding:"required"`
	EncryptedKey       string `json:"encryptedKey"  binding:"required"`
	KeyDecryptionNonce string `json:"keyDecryptionNonce"  binding:"required"`
}

// MoveFilesRequest represents movement of file between two collections
type MoveFilesRequest struct {
	FromCollectionID int64                `json:"fromCollectionID" binding:"required"`
	ToCollectionID   int64                `json:"toCollectionID" binding:"required"`
	Files            []CollectionFileItem `json:"files" binding:"required"`
}
