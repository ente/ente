package cast

import "github.com/google/uuid"

// CastRequest ..
type CastRequest struct {
	CollectionID int64  `json:"collectionID" binding:"required"`
	CastToken    string `json:"castToken" binding:"required"`
	EncPayload   string `json:"encPayload" binding:"required"`
	DeviceCode   string `json:"deviceCode" binding:"required"`
}

type RegisterDeviceRequest struct {
	PublicKey string `json:"publicKey" binding:"required"`
}

type AuthContext struct {
	CollectionID int64
	UserID       int64
}

type CastInfo struct {
	DeviceID     uuid.UUID `json:"deviceID"`
	CollectionID int64     `json:"collectionID"`
	DeviceIP     string    `json:"deviceIP"`
	LastUsedAt   int64     `json:"lastUsedAt"`
	DeviceName   *string   `json:"deviceName"`
}
