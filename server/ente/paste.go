package ente

import (
	"encoding/base64"
	"strings"
	"unicode"
)

const (
	pasteKdfSaltBytes                    = 16
	pasteKdfNonceMaxLength               = 64
	pasteKdfMemLimitInteractive          = 64 * 1024 * 1024
	pasteKdfOpsLimitInteractive          = 2
	pasteKdfMemLimitModerate             = 256 * 1024 * 1024
	pasteKdfOpsLimitModerate             = 3
	pasteDecryptionHeaderMaxLength       = 128
	pasteEncryptedPasteKeyMaxLength      = 256
	pasteEncryptedPasteKeyNonceMaxLength = 128
)

type CreatePasteRequest struct {
	EncryptedData          string `json:"encryptedData" binding:"required"`
	DecryptionHeader       string `json:"decryptionHeader" binding:"required"`
	EncryptedPasteKey      string `json:"encryptedPasteKey" binding:"required"`
	EncryptedPasteKeyNonce string `json:"encryptedPasteKeyNonce" binding:"required"`
	KdfNonce               string `json:"kdfNonce" binding:"required"`
	KdfMemLimit            int64  `json:"kdfMemLimit" binding:"required"`
	KdfOpsLimit            int64  `json:"kdfOpsLimit" binding:"required"`
}

func (r *CreatePasteRequest) Validate(maxCiphertextBytes int) error {
	if strings.TrimSpace(r.EncryptedData) == "" || strings.TrimSpace(r.DecryptionHeader) == "" {
		return NewBadRequestWithMessage("invalid encrypted payload")
	}
	if len(r.EncryptedData) > maxCiphertextBytes || len(r.DecryptionHeader) > pasteDecryptionHeaderMaxLength {
		return NewBadRequestWithMessage("encrypted payload too large")
	}

	if strings.TrimSpace(r.EncryptedPasteKey) == "" ||
		strings.TrimSpace(r.EncryptedPasteKeyNonce) == "" ||
		strings.TrimSpace(r.KdfNonce) == "" {
		return NewBadRequestWithMessage("invalid key material")
	}
	if len(r.EncryptedPasteKey) > pasteEncryptedPasteKeyMaxLength || len(r.EncryptedPasteKeyNonce) > pasteEncryptedPasteKeyNonceMaxLength {
		return NewBadRequestWithMessage("key material too large")
	}
	if len(r.KdfNonce) > pasteKdfNonceMaxLength {
		return NewBadRequestWithMessage("invalid key derivation parameters")
	}
	kdfNonce, err := base64.StdEncoding.DecodeString(r.KdfNonce)
	if err != nil {
		kdfNonce, err = base64.RawStdEncoding.DecodeString(r.KdfNonce)
	}
	if err != nil || len(kdfNonce) != pasteKdfSaltBytes {
		return NewBadRequestWithMessage("invalid key derivation parameters")
	}
	if !validPasteKdfCostParams(r.KdfMemLimit, r.KdfOpsLimit) {
		return NewBadRequestWithMessage("invalid key derivation parameters")
	}
	return nil
}

func validPasteKdfCostParams(memLimit, opsLimit int64) bool {
	return (memLimit == pasteKdfMemLimitInteractive && opsLimit == pasteKdfOpsLimitInteractive) ||
		(memLimit == pasteKdfMemLimitModerate && opsLimit == pasteKdfOpsLimitModerate)
}

type CreatePasteResponse struct {
	AccessToken string `json:"accessToken"`
	ExpiresAt   int64  `json:"expiresAt"`
}

type PasteTokenRequest struct {
	AccessToken string `json:"accessToken" binding:"required"`
}

func (r *PasteTokenRequest) Validate() error {
	token := strings.TrimSpace(r.AccessToken)
	if token == "" {
		return NewBadRequestWithMessage("access token required")
	}
	if len(token) < 6 || len(token) > 32 {
		return NewBadRequestWithMessage("invalid access token")
	}
	if !isAlphaNumeric(token) {
		return NewBadRequestWithMessage("invalid access token")
	}
	return nil
}

type PastePayload struct {
	EncryptedData          string `json:"encryptedData"`
	DecryptionHeader       string `json:"decryptionHeader"`
	EncryptedPasteKey      string `json:"encryptedPasteKey"`
	EncryptedPasteKeyNonce string `json:"encryptedPasteKeyNonce"`
	KdfNonce               string `json:"kdfNonce"`
	KdfMemLimit            int64  `json:"kdfMemLimit"`
	KdfOpsLimit            int64  `json:"kdfOpsLimit"`
}

func isAlphaNumeric(s string) bool {
	for _, r := range s {
		if !unicode.IsLetter(r) && !unicode.IsDigit(r) {
			return false
		}
	}
	return true
}
