package userentity

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/base"
)

type EntityType string

const (
	Location EntityType = "location"
	// Person entity is deprecated and will be removed in the future.
	Person EntityType = "person"
	// CGroup replaces Person; its data is gzipped before encryption.
	CGroup       EntityType = "cgroup"
	SmartAlbum   EntityType = "smart_album"
	Memory       EntityType = "memory"
	Contact      EntityType = "contact"
	Space        EntityType = "space"
	LibraryShare EntityType = "library_share"
)

func (et EntityType) IsValid() error {
	switch et {
	case Location, Person, CGroup, SmartAlbum, Memory, Contact, Space, LibraryShare:
		return nil
	}
	return ente.NewBadRequestWithMessage(fmt.Sprintf("Invalid EntityType: %s", et))
}

func (et EntityType) GetNewID() (*string, error) {
	return base.NewID(strings.ToLower(string(et)))
}

func (et EntityType) CanRestoreDeletedData() bool {
	return et == SmartAlbum || et == LibraryShare
}

type EntityKey struct {
	UserID       int64      `json:"userID" binding:"required"`
	Type         EntityType `json:"type" binding:"required"`
	EncryptedKey string     `json:"encryptedKey" binding:"required"`
	Header       string     `json:"header" binding:"required"`
	CreatedAt    int64      `json:"createdAt" binding:"required"`
}

type EntityData struct {
	ID            string     `json:"id" binding:"required"`
	UserID        int64      `json:"userID" binding:"required"`
	Type          EntityType `json:"type" binding:"required"`
	EncryptedData *string    `json:"encryptedData" binding:"required"`
	Header        *string    `json:"header" binding:"required"`
	IsDeleted     bool       `json:"isDeleted" binding:"required"`
	CreatedAt     int64      `json:"createdAt" binding:"required"`
	UpdatedAt     int64      `json:"updatedAt" binding:"required"`
}

type EntityKeyRequest struct {
	Type         EntityType `json:"type" binding:"required"`
	EncryptedKey string     `json:"encryptedKey" binding:"required"`
	Header       string     `json:"header" binding:"required"`
}

type GetEntityKeyRequest struct {
	Type EntityType `form:"type" binding:"required"`
}

type EntityDataRequest struct {
	Type          EntityType `json:"type" binding:"required"`
	EncryptedData string     `json:"encryptedData" binding:"required"`
	Header        string     `json:"header" binding:"required"`
	ID            *string    `json:"id"`
}

func (edr *EntityDataRequest) IsValid(userID int64) error {
	if err := edr.Type.IsValid(); err != nil {
		return err
	}
	switch edr.Type {
	case SmartAlbum:
		if edr.ID == nil {
			return ente.NewBadRequestWithMessage("ID is required for SmartAlbum entity type")
		}
		if !strings.HasPrefix(*edr.ID, fmt.Sprintf("sa_%d_", userID)) {
			return ente.NewBadRequestWithMessage(fmt.Sprintf("ID %s is not valid for SmartAlbum entity type", *edr.ID))
		}
	case LibraryShare:
		if edr.ID == nil {
			return ente.NewBadRequestWithMessage("ID is required for LibraryShare entity type")
		}
		parts := strings.Split(*edr.ID, "_")
		if len(parts) != 3 || parts[0] != "ls" {
			return ente.NewBadRequestWithMessage(fmt.Sprintf("ID %s is not valid for LibraryShare entity type", *edr.ID))
		}
		ownerID, ownerErr := strconv.ParseInt(parts[1], 10, 64)
		recipientID, recipientErr := strconv.ParseInt(parts[2], 10, 64)
		if ownerErr != nil || recipientErr != nil || ownerID != userID || recipientID <= 0 || recipientID == userID || *edr.ID != fmt.Sprintf("ls_%d_%d", ownerID, recipientID) {
			return ente.NewBadRequestWithMessage(fmt.Sprintf("ID %s is not valid for LibraryShare entity type", *edr.ID))
		}
	}
	return nil
}

type UpdateEntityDataRequest struct {
	ID                string     `json:"id" binding:"required"`
	Type              EntityType `json:"type" binding:"required"`
	EncryptedData     string     `json:"encryptedData" binding:"required"`
	Header            string     `json:"header" binding:"required"`
	ExpectedUpdatedAt *int64     `json:"expectedUpdatedAt"`
}

func (uedr *UpdateEntityDataRequest) IsValid() error {
	if err := uedr.Type.IsValid(); err != nil {
		return err
	}
	if uedr.Type == LibraryShare {
		if uedr.ExpectedUpdatedAt == nil || *uedr.ExpectedUpdatedAt <= 0 {
			return ente.NewBadRequestWithMessage("expectedUpdatedAt is required for LibraryShare entity type")
		}
	}
	return nil
}

type GetEntityDiffRequest struct {
	Type EntityType `form:"type" binding:"required"`
	// Keep this a pointer so binding accepts zero.
	SinceTime *int64 `form:"sinceTime" binding:"required"`
	Limit     int16  `form:"limit" binding:"required"`
}
