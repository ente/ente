package jwt

import (
	"errors"

	"github.com/ente/museum/pkg/utils/time"
)

var ErrTokenExpired = errors.New("token expired")

type ClaimScope string

const (
	PAYMENT        ClaimScope = "PAYMENT"
	FAMILIES       ClaimScope = "FAMILIES"
	ACCOUNTS       ClaimScope = "ACCOUNTS"
	DELETE_ACCOUNT ClaimScope = "DELETE_ACCOUNT"
	RestoreAccount ClaimScope = "RestoreAccount"
)

func (c ClaimScope) Ptr() *ClaimScope {
	return &c
}

type WebCommonJWTClaim struct {
	UserID     int64       `json:"userID,omitempty"`
	ExpiryTime int64       `json:"expiryTime,omitempty"`
	Email      string      `json:"email,omitempty"`
	ClaimScope *ClaimScope `json:"claimScope,omitempty"`
}

func (w *WebCommonJWTClaim) GetScope() ClaimScope {
	if w.ClaimScope == nil {
		return PAYMENT
	}
	return *w.ClaimScope
}

func (w WebCommonJWTClaim) Valid() error {
	if w.ExpiryTime < time.Microseconds() {
		return ErrTokenExpired
	}
	return nil
}

// LinkPasswordClaim refer to token granted post link password verification
type LinkPasswordClaim struct {
	PassHash   string `json:"passKey"`
	ExpiryTime int64  `json:"expiryTime"`
}

func (c LinkPasswordClaim) Valid() error {
	if c.ExpiryTime < time.Microseconds() {
		return ErrTokenExpired
	}
	return nil
}

// PasteGuardClaim gates one-time paste consumption.
type PasteGuardClaim struct {
	AccessToken   string `json:"accessToken"`
	UserAgentHash string `json:"userAgentHash"`
	ExpiryTime    int64  `json:"expiryTime"`
}

func (c PasteGuardClaim) Valid() error {
	if c.ExpiryTime < time.Microseconds() {
		return ErrTokenExpired
	}
	return nil
}
