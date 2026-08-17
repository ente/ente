package ente

import (
	"database/sql/driver"
	"encoding/json"

	"github.com/ente/stacktrace"
)

var ValidCollectionTypes = []string{"album", "folder", "favorites", "uncategorized"}

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
	// Per-sharee settings such as timeline visibility.
	SharedMagicMetadata *MagicMetadata `json:"sharedMagicMetadata,omitempty"`
}

func (c *Collection) AllowSharing() bool {
	if c == nil {
		return false
	}
	if c.Type == "uncategorized" {
		return false
	}
	return true
}

func (c *Collection) AllowParticipantSharing(role CollectionParticipantRole) bool {
	return c != nil && (c.Type != "uncategorized" || role == VIEWER)
}

func (c *Collection) AllowDelete() bool {
	if c == nil {
		return false
	}
	if c.Type == "favorites" || c.Type == "uncategorized" {
		return false
	}
	return true
}

type CollectionUser struct {
	ID    int64  `json:"id"`
	Email string `json:"email"`
	// Deprecated
	Name string                    `json:"name"`
	Role CollectionParticipantRole `json:"role"`
}

type CollectionAttributes struct {
	EncryptedPath       string `json:"encryptedPath,omitempty"`
	PathDecryptionNonce string `json:"pathDecryptionNonce,omitempty"`
	Version             int    `json:"version"`
}

func (ca CollectionAttributes) Value() (driver.Value, error) {
	return json.Marshal(ca)
}

func (ca *CollectionAttributes) Scan(value interface{}) error {
	b, ok := value.([]byte)
	if !ok {
		return stacktrace.NewError("type assertion to []byte failed")
	}

	return json.Unmarshal(b, &ca)
}

type AlterShareRequest struct {
	CollectionID int64                      `json:"collectionID" binding:"required"`
	Email        string                     `json:"email" binding:"required"`
	EncryptedKey string                     `json:"encryptedKey"`
	Role         *CollectionParticipantRole `json:"role"`
}

type CollectionShareSource string

const (
	ManualShare    CollectionShareSource = "manual"
	AutomaticShare CollectionShareSource = "automatic"
)

func (s CollectionShareSource) IsValid() bool {
	return s == ManualShare || s == AutomaticShare
}

type CollectionShareStatus string

const (
	CollectionShared               CollectionShareStatus = "shared"
	CollectionAlreadyShared        CollectionShareStatus = "already_shared"
	CollectionUnshared             CollectionShareStatus = "unshared"
	CollectionAlreadyUnshared      CollectionShareStatus = "already_unshared"
	CollectionNotShared            CollectionShareStatus = "not_shared"
	CollectionBlockedPriorRemoval  CollectionShareStatus = "blocked_previous_removal"
	CollectionShareOperationFailed CollectionShareStatus = "failed"
)

const MaxCollectionShareBatchSize = 100

type BulkCollectionShareItem struct {
	CollectionID int64                     `json:"collectionID" binding:"required"`
	EncryptedKey string                    `json:"encryptedKey" binding:"required"`
	Role         CollectionParticipantRole `json:"role" binding:"required"`
}

type BulkCollectionShareRequest struct {
	RecipientUserID int64                     `json:"recipientUserID" binding:"required"`
	RecipientEmail  string                    `json:"recipientEmail" binding:"required"`
	Source          CollectionShareSource     `json:"source" binding:"required"`
	Collections     []BulkCollectionShareItem `json:"collections" binding:"required"`
}

type BulkCollectionUnshareRequest struct {
	RecipientUserID int64                 `json:"recipientUserID" binding:"required"`
	Source          CollectionShareSource `json:"source" binding:"required"`
	CollectionIDs   []int64               `json:"collectionIDs" binding:"required"`
}

type BulkCollectionShareResult struct {
	CollectionID int64                 `json:"collectionID"`
	Status       CollectionShareStatus `json:"status"`
}

type JoinCollectionViaLinkRequest struct {
	CollectionID int64  `json:"collectionID" binding:"required"`
	EncryptedKey string `json:"encryptedKey" binding:"required"`
}

type AddFilesRequest struct {
	CollectionID int64                `json:"collectionID" binding:"required"`
	Files        []CollectionFileItem `json:"files" binding:"required"`
}

type CopyFileSyncRequest struct {
	SrcCollectionID     int64                `json:"srcCollectionID" binding:"required"`
	DstCollection       int64                `json:"dstCollectionID" binding:"required"`
	CollectionFileItems []CollectionFileItem `json:"files" binding:"required"`
}

type CopyResponse struct {
	OldToNewFileIDMap map[int64]int64 `json:"oldToNewFileIDMap"`
}

type RemoveFilesRequest struct {
	CollectionID int64   `json:"collectionID" binding:"required"`
	FileIDs      []int64 `json:"fileIDs"`
}

// Files owned by the collection owner must be moved, not removed.
type RemoveFilesV3Request struct {
	CollectionID int64   `json:"collectionID" binding:"required"`
	FileIDs      []int64 `json:"fileIDs"  binding:"required"`
}

type SuggestDeleteRequest struct {
	CollectionID int64   `json:"collectionID" binding:"required"`
	FileIDs      []int64 `json:"fileIDs" binding:"required"`
}

type RenameRequest struct {
	CollectionID        int64  `json:"collectionID" binding:"required"`
	EncryptedName       string `json:"encryptedName" binding:"required"`
	NameDecryptionNonce string `json:"nameDecryptionNonce" binding:"required"`
}

type UpdateCollectionMagicMetadata struct {
	ID            int64         `json:"id" binding:"required"`
	MagicMetadata MagicMetadata `json:"magicMetadata" binding:"required"`
}

type CollectionFileItem struct {
	ID                 int64  `json:"id" binding:"required"`
	EncryptedKey       string `json:"encryptedKey"  binding:"required"`
	KeyDecryptionNonce string `json:"keyDecryptionNonce"  binding:"required"`
}

type MoveFilesRequest struct {
	FromCollectionID int64                `json:"fromCollectionID" binding:"required"`
	ToCollectionID   int64                `json:"toCollectionID" binding:"required"`
	Files            []CollectionFileItem `json:"files" binding:"required"`
}
