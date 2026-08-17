package userentity

import (
	"fmt"
	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/base"
	"strings"
)

type EntityType string

const (
	Location EntityType = "location"
	// Person entity is deprecated and will be removed in the future.
	Person EntityType = "person"
	// CGroup replaces Person; its data is gzipped before encryption.
	CGroup     EntityType = "cgroup"
	SmartAlbum EntityType = "smart_album"
	Memory     EntityType = "memory"
	Contact    EntityType = "contact"
	Space      EntityType = "space"
)

func (et EntityType) IsValid() error {
	switch et {
	case Location, Person, CGroup, SmartAlbum, Memory, Contact, Space:
		return nil
	}
	return ente.NewBadRequestWithMessage(fmt.Sprintf("Invalid EntityType: %s", et))
}

func (et EntityType) GetNewID() (*string, error) {
	return base.NewID(strings.ToLower(string(et)))
}

func (et EntityType) CanRestoreDeletedData() bool {
	return et == SmartAlbum
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
		return nil
	default:
		return nil
	}
}

type UpdateEntityDataRequest struct {
	ID            string     `json:"id" binding:"required"`
	Type          EntityType `json:"type" binding:"required"`
	EncryptedData string     `json:"encryptedData" binding:"required"`
	Header        string     `json:"header" binding:"required"`
}

type GetEntityDiffRequest struct {
	Type EntityType `form:"type" binding:"required"`
	// Keep this a pointer so binding accepts zero.
	SinceTime *int64 `form:"sinceTime" binding:"required"`
	Limit     int16  `form:"limit" binding:"required"`
}
