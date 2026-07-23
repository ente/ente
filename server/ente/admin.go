package ente

import (
	"errors"
	"fmt"
	"time"
)

// GetEmailsFromHashesRequest represents a request to convert hashes
type GetEmailsFromHashesRequest struct {
	Hashes []string `json:"hashes"`
}

// Admin API request to disable 2FA for a user account.
//
// This is used when we get a user request to reset their 2FA when they might've
// lost access to their 2FA codes. We verify their identity out of band.
type DisableTwoFactorRequest struct {
	UserID int64 `json:"userID" binding:"required"`
}

type UpdateReferralCodeRequest struct {
	UserID int64  `json:"userID" binding:"required"`
	Code   string `json:"code" binding:"required"`
}

type AdminOttReq struct {
	Email      string `json:"email" binding:"required"`
	Code       string `json:"code" binding:"required"`
	App        App    `json:"app" binding:"required"`
	ExpiryTime int64  `json:"expiryTime" binding:"required"`
}

type LogoutSessionReq struct {
	Token  string `json:"token" binding:"required"`
	UserID int64  `json:"userID" binding:"required"`
}

type TokenInfo struct {
	CreationTime int64  `json:"creationTime"`
	LastUsedTime int64  `json:"lastUsedTime"`
	UA           string `json:"ua"`
	IsDeleted    bool   `json:"isDeleted"`
	App          App    `json:"app"`
}

func (a AdminOttReq) Validate() error {
	if !a.App.IsValid() {
		return errors.New("invalid app")
	}
	if a.ExpiryTime < time.Now().UnixMicro() {
		return errors.New("expiry time should be in future")
	}
	if len(a.Code) < 6 {
		return errors.New("invalid code length, should be at least 6 digit")
	}
	return nil
}

type AdminOpsForUserRequest struct {
	UserID   int64 `json:"userID" binding:"required"`
	EmailMFA *bool `json:"emailMFA"`
}

// ReQueueItemRequest puts an item back into the queue for processing.
type ReQueueItemRequest struct {
	ID        int64  `json:"id" binding:"required"`
	QueueName string `json:"queueName" binding:"required"`
}

// RecoverAccount is used to recover accounts which are in soft-delete state.
type RecoverAccountRequest struct {
	UserID  int64  `json:"userID" binding:"required"`
	EmailID string `json:"emailID" binding:"required"`
}

// UpdateSubscriptionRequest is used to update a user's subscription
type UpdateSubscriptionRequest struct {
	AdminID         int64                  `json:"-"`
	UserID          int64                  `json:"userID" binding:"required"`
	Storage         int64                  `json:"storage" binding:"required"`
	PaymentProvider PaymentProvider        `json:"paymentProvider"`
	TransactionID   string                 `json:"transactionID" binding:"required"`
	ProductID       string                 `json:"productID" binding:"required"`
	ExpiryTime      int64                  `json:"expiryTime" binding:"required"`
	Attributes      SubscriptionAttributes `json:"attributes"`
}

type ChangeEmailRequest struct {
	UserID int64  `json:"userID" binding:"required"`
	Email  string `json:"email" binding:"required"`
}

type AddOnAction string

const (
	ADD    AddOnAction = "ADD"
	REMOVE AddOnAction = "REMOVE"
	UPDATE AddOnAction = "UPDATE"
)

type SupportUpdateBonus struct {
	BonusType   string      `json:"bonusType" binding:"required"`
	Action      AddOnAction `json:"action" binding:"required"`
	UserID      int64       `json:"userID" binding:"required"`
	Year        int         `json:"year"`
	StorageInGB int64       `json:"storageInGB"`
	Testing     bool        `json:"testing"`
	StorageInMB int64       `json:"storageInMB"`
	Minute      int64       `json:"minute"`
}

func (u SupportUpdateBonus) UpdateLog() string {
	if u.Testing {
		return fmt.Sprintf("SupportUpdateBonus: %s, storageInMB: %d, minute: %d", u.Action, u.StorageInMB, u.Minute)
	} else {
		return fmt.Sprintf("%s: %s, storageInGB: %d, year: %d", u.BonusType, u.Action, u.StorageInGB, u.Year)
	}
}

func (u SupportUpdateBonus) Validate() error {
	usesFlexibleAddOnRules := u.BonusType == "ADD_ON_SUPPORT" || u.BonusType == "ADD_ON_NON_PROFIT"
	if u.BonusType != "ADD_ON_SUPPORT" && u.BonusType != "ADD_ON_NON_PROFIT" && u.BonusType != "ADD_ON_BF_2023" && u.BonusType != "ADD_ON_BF_2024" {
		return errors.New("invalid bonus type")
	}
	if u.Action == ADD || u.Action == UPDATE {
		if u.Testing {
			if u.StorageInMB == 0 && u.Minute == 0 {
				return errors.New("invalid input, set in MB and minute for test")
			}
		} else {
			if usesFlexibleAddOnRules {
				if u.Year == 0 || u.Year > 100 {
					return errors.New("invalid input for year, only 1-100")
				}
				if u.StorageInGB == 0 || u.StorageInGB > 2000 {
					return errors.New("invalid GB storage, only 1-2000")
				}
			} else {
				if u.StorageInGB != 50 && u.StorageInGB != 200 && u.StorageInGB != 500 && u.StorageInGB != 1000 && u.StorageInGB != 2000 {
					return errors.New("invalid input for deal, only 50, 200, 500, 1000, 2000 allowed")
				}
				if u.Year != 3 && u.Year != 5 && u.Year != 10 {
					return errors.New("invalid input for year, only 3 or 5 or 10")
				}
			}
		}
	}
	return nil
}
