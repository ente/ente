package ente

import (
	"encoding/json"
	"time"
)

type PushTokenRequest struct {
	FCMToken             string  `json:"fcmToken" binding:"required"`
	APNSToken            string  `json:"apnsToken"`
	Platform             *string `json:"platform" binding:"required,oneof=ios android"`
	LastNotificationTime int64
}

type PushToken struct {
	UserID         int64  `json:"userID"`
	FCMToken       string `json:"fcmToken"`
	CreatedAt      int64  `json:"createdAt"`
	LastNotifiedAt int64  `json:"lastNotifiedAt"`
}

func (pt *PushToken) MarshalJSON() ([]byte, error) {
	trimmedToken := pt.FCMToken
	if len(trimmedToken) > 9 {
		trimmedToken = trimmedToken[0:9]
	}
	return json.Marshal(&struct {
		UserID         int64  `json:"userID"`
		TrimmedToken   string `json:"trimmedToken"`
		CreatedAt      string `json:"createdAt"`
		LastNotifiedAt string `json:"LastNotifiedAt"`
	}{
		UserID:         pt.UserID,
		TrimmedToken:   trimmedToken,
		CreatedAt:      time.Unix(pt.CreatedAt/1000000, 0).String(),
		LastNotifiedAt: time.Unix(pt.LastNotifiedAt/1000000, 0).String(),
	})
}
