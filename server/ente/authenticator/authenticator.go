package authenticator

import "github.com/google/uuid"

type Key struct {
	UserID       int64  `json:"userID" binding:"required"`
	EncryptedKey string `json:"encryptedKey" binding:"required"`
	Header       string `json:"header" binding:"required"`
	CreatedAt    int64  `json:"createdAt" binding:"required"`
}

type Entity struct {
	ID            uuid.UUID `json:"id" binding:"required"`
	UserID        int64     `json:"userID" binding:"required"`
	EncryptedData *string   `json:"encryptedData" binding:"required"`
	Header        *string   `json:"header" binding:"required"`
	IsDeleted     bool      `json:"isDeleted" binding:"required"`
	CreatedAt     int64     `json:"createdAt" binding:"required"`
	UpdatedAt     int64     `json:"updatedAt" binding:"required"`
}

type CreateKeyRequest struct {
	EncryptedKey string `json:"encryptedKey" binding:"required"`
	Header       string `json:"header" binding:"required"`
}

type CreateEntityRequest struct {
	EncryptedData string `json:"encryptedData" binding:"required"`
	Header        string `json:"header" binding:"required"`
}

type UpdateEntityRequest struct {
	ID            uuid.UUID `json:"id" binding:"required"`
	EncryptedData string    `json:"encryptedData" binding:"required"`
	Header        string    `json:"header" binding:"required"`
}

type GetEntityDiffRequest struct {
	// Keep this a pointer so binding accepts zero.
	SinceTime *int64 `form:"sinceTime" binding:"required"`
	Limit     int16  `form:"limit" binding:"required"`
}
