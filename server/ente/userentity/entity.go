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
	//Deprecated ..
	Person EntityType = "person"
	// CGroup is a new version of Person entity, where the data is gzipped before encryption
	CGroup EntityType = "cgroup"
	// SmartAlbum is a new entity type for storing smart album config data
	SmartAlbum EntityType = "smart_album"
	// Memory is the entity type for memory share encryption keys
	Memory EntityType = "memory"
	// Contact is the entity type for the shared contact root key.
	Contact EntityType = "contact"
	// Space is the entity type for the space root key.
	Space EntityType = "space"
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

// EntityData represents a single UserEntity
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

// EntityKeyRequest represents a request to create entity data encryption key for a given EntityType
type EntityKeyRequest struct {
	Type         EntityType `json:"type" binding:"required"`
	EncryptedKey string     `json:"encryptedKey" binding:"required"`
	Header       string     `json:"header" binding:"required"`
}

// GetEntityKeyRequest represents a request to get entity key for given EntityType
type GetEntityKeyRequest struct {
	Type EntityType `form:"type" binding:"required"`
}

// EntityDataRequest is used to create a new entity data of given EntityType
type EntityDataRequest struct {
	Type          EntityType `json:"type" binding:"required"`
	EncryptedData string     `json:"encryptedData" binding:"required"`
	Header        string     `json:"header" binding:"required"`
	ID            *string    `json:"id"` // Optional ID, if not provided a new ID will be generated
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
		// check if ID starts with sa_userid_ or not
		if !strings.HasPrefix(*edr.ID, fmt.Sprintf("sa_%d_", userID)) {
			return ente.NewBadRequestWithMessage(fmt.Sprintf("ID %s is not valid for SmartAlbum entity type", *edr.ID))
		}
		return nil
	default:
		return nil
	}
}

// UpdateEntityDataRequest updates the current entity
type UpdateEntityDataRequest struct {
	ID            string     `json:"id" binding:"required"`
	Type          EntityType `json:"type" binding:"required"`
	EncryptedData string     `json:"encryptedData" binding:"required"`
	Header        string     `json:"header" binding:"required"`
}

// GetEntityDiffRequest returns the diff of entities since the given time
type GetEntityDiffRequest struct {
	Type EntityType `form:"type" binding:"required"`
	// SinceTime *int64. Pointer allows us to pass 0 value otherwise binding fails for zero Value.
	SinceTime *int64 `form:"sinceTime" binding:"required"`
	Limit     int16  `form:"limit" binding:"required"`
}
