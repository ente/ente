package contact

import (
	"fmt"
	"strings"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/base"
)

type AttachmentType string

const (
	ProfilePicture AttachmentType = "profile_picture"

	contactIDPrefix    = "ct"
	attachmentIDPrefix = "ua"

	MaxProfilePictureEncryptedSize int64 = 512 * 1024
)

type AttachmentPolicy struct {
	Type             AttachmentType
	SlotColumn       string
	MaxEncryptedSize int64
}

var attachmentPolicies = map[AttachmentType]AttachmentPolicy{
	ProfilePicture: {
		Type:             ProfilePicture,
		SlotColumn:       "profile_picture_attachment_id",
		MaxEncryptedSize: MaxProfilePictureEncryptedSize,
	},
}

type Entity struct {
	ID                         string  `json:"id" binding:"required"`
	UserID                     int64   `json:"userID" binding:"required"`
	ContactUserID              int64   `json:"contactUserID" binding:"required"`
	Email                      *string `json:"email"`
	ProfilePictureAttachmentID *string `json:"profilePictureAttachmentID"`
	EncryptedKey               *[]byte `json:"encryptedKey"`
	EncryptedData              *[]byte `json:"encryptedData"`
	IsDeleted                  bool    `json:"isDeleted" binding:"required"`
	CreatedAt                  int64   `json:"createdAt" binding:"required"`
	UpdatedAt                  int64   `json:"updatedAt" binding:"required"`
}

type CreateRequest struct {
	ContactUserID int64  `json:"contactUserID" binding:"required"`
	EncryptedKey  []byte `json:"encryptedKey" binding:"required"`
	EncryptedData []byte `json:"encryptedData" binding:"required"`
}

func (r CreateRequest) Validate() error {
	if r.ContactUserID <= 0 {
		return ente.NewBadRequestWithMessage("contactUserID must be greater than 0")
	}
	if len(r.EncryptedKey) == 0 {
		return ente.NewBadRequestWithMessage("encryptedKey is required")
	}
	if len(r.EncryptedData) == 0 {
		return ente.NewBadRequestWithMessage("encryptedData is required")
	}
	return nil
}

type UpdateRequest struct {
	ContactUserID int64  `json:"contactUserID" binding:"required"`
	EncryptedData []byte `json:"encryptedData" binding:"required"`
}

func (r UpdateRequest) Validate() error {
	if r.ContactUserID <= 0 {
		return ente.NewBadRequestWithMessage("contactUserID must be greater than 0")
	}
	if len(r.EncryptedData) == 0 {
		return ente.NewBadRequestWithMessage("encryptedData is required")
	}
	return nil
}

type DiffRequest struct {
	SinceTime *int64 `form:"sinceTime" binding:"required"`
	Limit     int16  `form:"limit" binding:"required"`
}

type AttachmentUploadURLRequest struct {
	ContentLength int64  `json:"contentLength" binding:"required"`
	ContentMD5    string `json:"contentMD5" binding:"required"`
}

func (r AttachmentUploadURLRequest) Validate(policy AttachmentPolicy) error {
	if r.ContentLength <= 0 {
		return ente.NewBadRequestWithMessage("contentLength must be greater than 0")
	}
	if r.ContentLength > policy.MaxEncryptedSize {
		return ente.NewBadRequestWithMessage(
			fmt.Sprintf("%s must be <= %d bytes", policy.Type, policy.MaxEncryptedSize),
		)
	}
	if strings.TrimSpace(r.ContentMD5) == "" {
		return ente.NewBadRequestWithMessage("contentMD5 is required")
	}
	return nil
}

type AttachmentUploadURL struct {
	AttachmentID string `json:"attachmentID" binding:"required"`
	URL          string `json:"url" binding:"required"`
}

type CommitAttachmentRequest struct {
	AttachmentID string `json:"attachmentID" binding:"required"`
	Size         int64  `json:"size" binding:"required"`
}

func (r CommitAttachmentRequest) Validate(policy AttachmentPolicy) error {
	if !IsValidAttachmentID(r.AttachmentID) {
		return ente.NewBadRequestWithMessage("invalid attachmentID")
	}
	if r.Size <= 0 {
		return ente.NewBadRequestWithMessage("size must be greater than 0")
	}
	if r.Size > policy.MaxEncryptedSize {
		return ente.NewBadRequestWithMessage(
			fmt.Sprintf("%s must be <= %d bytes", policy.Type, policy.MaxEncryptedSize),
		)
	}
	return nil
}

type SignedURLResponse struct {
	URL string `json:"url" binding:"required"`
}

type Attachment struct {
	AttachmentID       string         `json:"attachmentID" binding:"required"`
	UserID             int64          `json:"userID" binding:"required"`
	AttachmentType     AttachmentType `json:"attachmentType" binding:"required"`
	Size               int64          `json:"size" binding:"required"`
	LatestBucket       string         `json:"latestBucket" binding:"required"`
	ReplicatedBuckets  []string       `json:"replicatedBuckets" binding:"required"`
	DeleteFromBuckets  []string       `json:"deleteFromBuckets" binding:"required"`
	InflightRepBuckets []string       `json:"inflightRepBuckets" binding:"required"`
	PendingSync        bool           `json:"pendingSync" binding:"required"`
	IsDeleted          bool           `json:"isDeleted" binding:"required"`
	SyncLockedTill     int64          `json:"syncLockedTill" binding:"required"`
	CreatedAt          int64          `json:"createdAt" binding:"required"`
	UpdatedAt          int64          `json:"updatedAt" binding:"required"`
}

func (a Attachment) ObjectKey() string {
	return AttachmentObjectKey(a.UserID, a.AttachmentType, a.AttachmentID)
}

func (at AttachmentType) IsValid() error {
	if _, ok := attachmentPolicies[at]; ok {
		return nil
	}
	return ente.NewBadRequestWithMessage(fmt.Sprintf("invalid attachment type: %s", at))
}

func (at AttachmentType) Policy() (AttachmentPolicy, error) {
	policy, ok := attachmentPolicies[at]
	if !ok {
		return AttachmentPolicy{}, ente.NewBadRequestWithMessage(
			fmt.Sprintf("invalid attachment type: %s", at),
		)
	}
	return policy, nil
}

func ParseAttachmentType(raw string) (AttachmentType, error) {
	attachmentType := AttachmentType(raw)
	if err := attachmentType.IsValid(); err != nil {
		return "", err
	}
	return attachmentType, nil
}

func NewContactID() string {
	return base.MustNewID(contactIDPrefix)
}

func NewAttachmentID() string {
	return base.MustNewID(attachmentIDPrefix)
}

func AttachmentObjectKey(userID int64, attachmentType AttachmentType, attachmentID string) string {
	return fmt.Sprintf("%d/user-attachments/%s/%s", userID, attachmentType, attachmentID)
}

func IsValidContactID(id string) bool {
	return strings.HasPrefix(id, contactIDPrefix+"_") && len(id) > len(contactIDPrefix)+1
}

func IsValidAttachmentID(id string) bool {
	return strings.HasPrefix(id, attachmentIDPrefix+"_") && len(id) > len(attachmentIDPrefix)+1
}
