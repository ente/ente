package ente

import (
	"github.com/google/uuid"
)

type SetupSRPRequest struct {
	SrpUserID   uuid.UUID `json:"srpUserID" binding:"required"`
	SRPSalt     string    `json:"srpSalt" binding:"required"`
	SRPVerifier string    `json:"srpVerifier" binding:"required"`
	SRPA        string    `json:"srpA"  binding:"required"`
}

type SetupSRPResponse struct {
	SetupID uuid.UUID `json:"setupID" binding:"required"`
	SRPB    string    `json:"srpB" binding:"required"`
}

type CompleteSRPSetupRequest struct {
	SetupID uuid.UUID `json:"setupID" binding:"required"`
	SRPM1   string    `json:"srpM1" binding:"required"`
}

type CompleteSRPSetupResponse struct {
	SetupID uuid.UUID `json:"setupID" binding:"required"`
	SRPM2   string    `json:"srpM2" binding:"required"`
}

type RecoverySrpSetupRequest struct {
	RecoveryID  uuid.UUID       `json:"recoveryID" binding:"required"`
	SetUpSRPReq SetupSRPRequest `json:"setupSRPRequest" binding:"required"`
}

type RecoveryUpdateSRPAndKeysRequest struct {
	RecoveryID uuid.UUID               `json:"recoveryID" binding:"required"`
	UpdateSrp  UpdateSRPAndKeysRequest `json:"updateSrpAndKeysRequest" binding:"required"`
}

type UpdateSRPAndKeysRequest struct {
	SetupID            uuid.UUID          `json:"setupID" binding:"required"`
	SRPM1              string             `json:"srpM1" binding:"required"`
	UpdateAttributes   *UpdateKeysRequest `json:"updatedKeyAttr"`
	LogOutOtherDevices *bool              `json:"logOutOtherDevices"`
}

func (r UpdateSRPAndKeysRequest) Validate() error {
	if r.UpdateAttributes == nil {
		return NewBadRequestWithMessage("updatedKeyAttr is required")
	}
	return r.UpdateAttributes.Validate()
}

type UpdateSRPSetupResponse struct {
	SetupID uuid.UUID `json:"setupID" binding:"required"`
	SRPM2   string    `json:"srpM2" binding:"required"`
}

type GetSRPAttributesRequest struct {
	Email string `form:"email" binding:"required"`
}

type GetSRPAttributesResponse struct {
	SRPUserID string `json:"srpUserID" binding:"required"`
	SRPSalt   string `json:"srpSalt"  binding:"required"`
	// MemLimit,OpsLimit,KekSalt are needed to derive the KeyEncryptionKey
	// on the client. Client generates the LoginKey from the KeyEncryptionKey
	// and treat that as UserInputPassword.
	MemLimit          int    `json:"memLimit" binding:"required"`
	OpsLimit          int    `json:"opsLimit" binding:"required"`
	KekSalt           string `json:"kekSalt" binding:"required"`
	IsEmailMFAEnabled bool   `json:"isEmailMFAEnabled" binding:"required"`
}

type CreateSRPSessionRequest struct {
	SRPUserID uuid.UUID `json:"srpUserID" binding:"required"`
	SRPA      string    `json:"srpA" binding:"required"`
}

type CreateSRPSessionResponse struct {
	SessionID uuid.UUID `json:"sessionID" binding:"required"`
	SRPB      string    `json:"srpB" binding:"required"`
}

type VerifySRPSessionRequest struct {
	SessionID uuid.UUID `json:"sessionID" binding:"required"`
	SRPUserID uuid.UUID `json:"srpUserID" binding:"required"`
	SRPM1     string    `json:"srpM1"`
}

type SRPSessionEntity struct {
	ID           uuid.UUID
	SRPUserID    uuid.UUID
	UserID       int64
	ServerKey    string
	SRP_A        string
	IsVerified   bool
	AttemptCount int32
	IsFake       bool
}

type SRPAuthEntity struct {
	UserID    int64
	SRPUserID uuid.UUID
	Salt      string
	Verifier  string
}

type SRPSetupEntity struct {
	ID        uuid.UUID
	SessionID uuid.UUID
	SRPUserID uuid.UUID
	UserID    int64
	Salt      string
	Verifier  string
}
