package ente

import "github.com/google/uuid"

type Passkey struct {
	ID           uuid.UUID `json:"id"`
	UserID       int64     `json:"userID"`
	FriendlyName string    `json:"friendlyName"`

	CreatedAt int64 `json:"createdAt"`
}

var MaxPasskeys = 10

type SetPasskeyRecoveryRequest struct {
	Secret string `json:"secret" binding:"required"`
	// The skip secret encrypted with the recovery key. Decrypting it during MFA
	// recovery proves possession of that key.
	UserSecretCipher string `json:"userSecretCipher" binding:"required"`
	UserSecretNonce  string `json:"userSecretNonce" binding:"required"`
}

type TwoFactorRecoveryStatus struct {
	AllowAdminReset          bool `json:"allowAdminReset" binding:"required"`
	IsPasskeyRecoveryEnabled bool `json:"isPasskeyRecoveryEnabled" binding:"required"`
}
