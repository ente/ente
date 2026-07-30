package filedata

import (
	"fmt"
	"github.com/ente/museum/ente"
)

type PutFileDataRequest struct {
	FileID           int64           `json:"fileID" binding:"required"`
	Type             ente.ObjectType `json:"type" binding:"required"`
	EncryptedData    *string         `json:"encryptedData,omitempty"`
	DecryptionHeader *string         `json:"decryptionHeader,omitempty"`
	Version          *int            `json:"version,omitempty"`
	// Used to ensure that the client has correct state before it tries to update the metadata
	LastUpdatedAt *int64 `json:"lastUpdatedAt,omitempty"`
}

func (r PutFileDataRequest) isEncDataPresent() bool {
	return r.EncryptedData != nil && r.DecryptionHeader != nil && *r.EncryptedData != "" && *r.DecryptionHeader != ""
}

func (r PutFileDataRequest) Validate() error {
	switch r.Type {
	case ente.MlData:
		if !r.isEncDataPresent() {
			return ente.NewBadRequestWithMessage("encryptedData and decryptionHeader (only) are required for derived meta")
		}
	default:
		return ente.NewBadRequestWithMessage(fmt.Sprintf("invalid object type %s", r.Type))
	}
	return nil
}
