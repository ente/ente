package ente

import "github.com/google/uuid"

type LegacyKitRecoveryStatus string
type LegacyKitVariant int32

const (
	LegacyKitRecoveryStatusWaiting   LegacyKitRecoveryStatus = "WAITING"
	LegacyKitRecoveryStatusReady     LegacyKitRecoveryStatus = "READY"
	LegacyKitRecoveryStatusBlocked   LegacyKitRecoveryStatus = "BLOCKED"
	LegacyKitRecoveryStatusCancelled LegacyKitRecoveryStatus = "CANCELLED"
	LegacyKitRecoveryStatusRecovered LegacyKitRecoveryStatus = "RECOVERED"
)

const (
	LegacyKitVariantTwoOfThree LegacyKitVariant = 1
)

type CreateLegacyKitRequest struct {
	ID                  uuid.UUID        `json:"id" binding:"required"`
	Variant             LegacyKitVariant `json:"variant" binding:"required"`
	NoticePeriodInHours *int             `json:"noticePeriodInHours" binding:"required"`
	// Base64(secretbox nonce || MAC || ciphertext) of the user's recovery key.
	EncryptedRecoveryBlob string `json:"encryptedRecoveryBlob" binding:"required"`
	// Base64(X25519 public key) derived deterministically from the kit secret.
	AuthPublicKey string `json:"authPublicKey" binding:"required"`
	// Base64(secretbox nonce || MAC || ciphertext) of owner-only part names and
	// stored share payloads used for listing and downloading cards again.
	EncryptedOwnerBlob string `json:"encryptedOwnerBlob" binding:"required"`
}

type LegacyKit struct {
	ID                  uuid.UUID        `json:"id"`
	Variant             LegacyKitVariant `json:"variant"`
	NoticePeriodInHours int32            `json:"noticePeriodInHours"`
	LegacyURL           string           `json:"legacyUrl"`
	// Base64(secretbox nonce || MAC || ciphertext) of owner-only part names and
	// stored share payloads used for listing and downloading cards again.
	EncryptedOwnerBlob    string                    `json:"encryptedOwnerBlob"`
	CreatedAt             int64                     `json:"createdAt"`
	UpdatedAt             int64                     `json:"updatedAt"`
	ActiveRecoverySession *LegacyKitRecoverySession `json:"activeRecoverySession,omitempty"`
}

type ListLegacyKitsResponse struct {
	Kits []*LegacyKit `json:"kits"`
}

type LegacyKitDownloadContentResponse struct {
	ID      uuid.UUID        `json:"id"`
	Variant LegacyKitVariant `json:"variant"`
	// Base64(secretbox nonce || MAC || ciphertext) of owner-only part names and
	// stored share payloads used for listing and downloading cards again.
	EncryptedOwnerBlob string `json:"encryptedOwnerBlob"`
}

type LegacyKitRecoverySession struct {
	ID     uuid.UUID               `json:"id"`
	KitID  uuid.UUID               `json:"kitID"`
	Status LegacyKitRecoveryStatus `json:"status"`
	// Remaining microseconds until recovery is ready, not an epoch timestamp.
	WaitTill  int64 `json:"waitTill"`
	CreatedAt int64 `json:"createdAt"`
}

type LegacyKitChallengeRequest struct {
	KitID uuid.UUID `json:"kitID" binding:"required"`
}

type LegacyKitChallengeResponse struct {
	KitID              uuid.UUID `json:"kitID"`
	EncryptedChallenge string    `json:"encryptedChallenge"`
	ExpiresAt          int64     `json:"expiresAt"`
}

type LegacyKitOpenRecoveryRequest struct {
	KitID           uuid.UUID `json:"kitID" binding:"required"`
	Challenge       string    `json:"challenge" binding:"required"`
	UsedPartIndexes []int     `json:"usedPartIndexes,omitempty"`
	Email           *string   `json:"email"`
}

type LegacyKitOpenRecoveryResponse struct {
	Session      LegacyKitRecoverySession `json:"session"`
	SessionToken string                   `json:"sessionToken"`
}

type LegacyKitRecoveryInitiator struct {
	// Share indexes reported by the recovery client as the shares used to
	// reconstruct the kit secret. This is an audit hint, not an authorization
	// primitive.
	UsedPartIndexes []int  `json:"usedPartIndexes,omitempty"`
	IP              string `json:"ip"`
	UserAgent       string `json:"userAgent"`
}

type LegacyKitOwnerRecoverySessionResponse struct {
	Session    *LegacyKitRecoverySession    `json:"session"`
	Initiators []LegacyKitRecoveryInitiator `json:"initiators"`
}

type LegacyKitSessionRequest struct {
	SessionID    uuid.UUID `json:"sessionID" binding:"required"`
	SessionToken string    `json:"sessionToken" binding:"required"`
}

type LegacyKitRecoveryInfoResponse struct {
	// Base64(secretbox nonce || MAC || ciphertext) of the user's recovery key.
	EncryptedRecoveryBlob string        `json:"encryptedRecoveryBlob"`
	UserKeyAttr           KeyAttributes `json:"userKeyAttr"`
}

type LegacyKitRecoverySrpSetupRequest struct {
	SessionID       uuid.UUID       `json:"sessionID" binding:"required"`
	SessionToken    string          `json:"sessionToken" binding:"required"`
	SetupSRPRequest SetupSRPRequest `json:"setupSRPRequest" binding:"required"`
}

type LegacyKitRecoveryUpdateSRPRequest struct {
	SessionID               uuid.UUID               `json:"sessionID" binding:"required"`
	SessionToken            string                  `json:"sessionToken" binding:"required"`
	UpdateSrpAndKeysRequest UpdateSRPAndKeysRequest `json:"updateSrpAndKeysRequest" binding:"required"`
}

type LegacyKitOwnerActionRequest struct {
	KitID uuid.UUID `json:"kitID" binding:"required"`
}

type UpdateLegacyKitRecoveryNoticeRequest struct {
	KitID               uuid.UUID `json:"kitID" binding:"required"`
	NoticePeriodInHours *int      `json:"noticePeriodInHours" binding:"required"`
}
