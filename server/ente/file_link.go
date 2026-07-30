package ente

import (
	"fmt"
	"github.com/ente/museum/pkg/utils/time"
)

// CreateFileUrl represents an encrypted file in the system
type CreateFileUrl struct {
	FileID                int64   `json:"fileID" binding:"required"`
	App                   App     `json:"app" binding:"required"`
	EncryptedFileKey      *string `json:"encryptedFileKey,omitempty"`
	EncryptedFileKeyNonce *string `json:"encryptedFileKeyNonce,omitempty"`
	KdfNonce              *string `json:"kdfNonce,omitempty"`
	KdfMemLimit           *int64  `json:"kdfMemLimit,omitempty"`
	KdfOpsLimit           *int64  `json:"kdfOpsLimit,omitempty"`
	EncryptedShareKey     *string `json:"encryptedShareKey,omitempty"`
}

// UpdateFileUrl ..
type UpdateFileUrl struct {
	LinkID          string `json:"linkID" binding:"required"`
	FileID          int64  `json:"fileID" binding:"required"`
	ValidTill       *int64 `json:"validTill"`
	DeviceLimit     *int   `json:"deviceLimit"`
	PassHash        *string
	Nonce           *string
	MemLimit        *int64
	OpsLimit        *int64
	EnableDownload  *bool `json:"enableDownload"`
	DisablePassword *bool `json:"disablePassword"`
}

func (ut *UpdateFileUrl) Validate() error {
	if ut.DeviceLimit == nil && ut.ValidTill == nil && ut.DisablePassword == nil &&
		ut.Nonce == nil && ut.PassHash == nil && ut.EnableDownload == nil {
		return NewBadRequestWithMessage("all parameters are missing")
	}

	if ut.DeviceLimit != nil && (*ut.DeviceLimit < 0 || *ut.DeviceLimit > 50) {
		return NewBadRequestWithMessage(fmt.Sprintf("device limit: %d out of range [0-50]", *ut.DeviceLimit))
	}

	if ut.ValidTill != nil && *ut.ValidTill != 0 && *ut.ValidTill < time.Microseconds() {
		return NewBadRequestWithMessage("valid till should be greater than current timestamp")
	}

	var allPassParamsMissing = ut.Nonce == nil && ut.PassHash == nil && ut.MemLimit == nil && ut.OpsLimit == nil
	var allPassParamsPresent = ut.Nonce != nil && ut.PassHash != nil && ut.MemLimit != nil && ut.OpsLimit != nil

	if !(allPassParamsMissing || allPassParamsPresent) {
		return NewBadRequestWithMessage("all password params should be either present or missing")
	}

	if allPassParamsPresent && ut.DisablePassword != nil && *ut.DisablePassword {
		return NewBadRequestWithMessage("can not set and disable password in same request")
	}
	return nil
}

type FileLinkRow struct {
	LinkID                string
	OwnerID               int64
	FileID                int64
	Token                 string
	DeviceLimit           int
	ValidTill             int64
	IsDisabled            bool
	PassHash              *string
	Nonce                 *string
	MemLimit              *int64
	OpsLimit              *int64
	EnableDownload        bool
	CreatedAt             int64
	UpdatedAt             int64
	EncryptedFileKey      *string
	EncryptedFileKeyNonce *string
	KdfNonce              *string
	KdfMemLimit           *int64
	KdfOpsLimit           *int64
	EncryptedShareKey     *string
}

type FileUrl struct {
	LinkID          string `json:"linkID" binding:"required"`
	URL             string `json:"url" binding:"required"`
	OwnerID         int64  `json:"ownerID" binding:"required"`
	FileID          int64  `json:"fileID" binding:"required"`
	IsDisabled      bool   `json:"isDisabled"`
	ValidTill       int64  `json:"validTill"`
	DeviceLimit     int    `json:"deviceLimit"`
	PasswordEnabled bool   `json:"passwordEnabled"`
	// Nonce contains the nonce value for the password if the link is password protected.
	Nonce                 *string `json:"nonce,omitempty"`
	MemLimit              *int64  `json:"memLimit,omitempty"`
	OpsLimit              *int64  `json:"opsLimit,omitempty"`
	EnableDownload        bool    `json:"enableDownload"`
	CreatedAt             int64   `json:"createdAt"`
	EncryptedFileKey      *string `json:"encryptedFileKey,omitempty"`
	EncryptedFileKeyNonce *string `json:"encryptedFileKeyNonce,omitempty"`
	KdfNonce              *string `json:"kdfNonce,omitempty"`
	KdfMemLimit           *int64  `json:"kdfMemLimit,omitempty"`
	KdfOpsLimit           *int64  `json:"kdfOpsLimit,omitempty"`
	EncryptedShareKey     *string `json:"encryptedShareKey,omitempty"`
}

type FileLinkAccessContext struct {
	LinkID    string
	IP        string
	UserAgent string
	FileID    int64
	OwnerID   int64
}

type FileLinkSecret struct {
	EncryptedFileKey      *string `json:"encryptedFileKey,omitempty"`
	EncryptedFileKeyNonce *string `json:"encryptedFileKeyNonce,omitempty"`
	KdfNonce              *string `json:"kdfNonce,omitempty"`
	KdfMemLimit           *int64  `json:"kdfMemLimit,omitempty"`
	KdfOpsLimit           *int64  `json:"kdfOpsLimit,omitempty"`
}
