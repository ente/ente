package ente

import (
	"github.com/google/uuid"
)

type MemberStatus string

const (
	SELF     MemberStatus = "SELF"
	CLOSED   MemberStatus = "CLOSED"
	INVITED  MemberStatus = "INVITED"
	ACCEPTED MemberStatus = "ACCEPTED"
	DECLINED MemberStatus = "DECLINED"
	REVOKED  MemberStatus = "REVOKED"
	REMOVED  MemberStatus = "REMOVED"
	LEFT     MemberStatus = "LEFT"
)

type InviteMemberRequest struct {
	Email        string `json:"email" binding:"required"`
	StorageLimit *int64 `json:"storageLimit" binding:"omitempty"`
}

type InviteInfoResponse struct {
	ID         uuid.UUID `json:"id" binding:"required"`
	AdminEmail string    `json:"adminEmail" binding:"required"`
}

type AcceptInviteResponse struct {
	AdminEmail string `json:"adminEmail" binding:"required"`
	Storage    int64  `json:"storage" binding:"required"`
	ExpiryTime int64  `json:"expiryTime" binding:"required"`
}

type AcceptInviteRequest struct {
	Token string `json:"token" binding:"required"`
}

type FamilyMember struct {
	ID           uuid.UUID    `json:"id" binding:"required"`
	Email        string       `json:"email" binding:"required"`
	Status       MemberStatus `json:"status" binding:"required"`
	StorageLimit *int64       `json:"storageLimit" binding:"omitempty"`
	UserID       *int64       `json:"userID"`
	// Do not expose usage for invited members.
	Usage        int64 `json:"usage"`
	IsAdmin      bool  `json:"isAdmin"`
	MemberUserID int64 `json:"-"`
	AdminUserID  int64 `json:"-"`
}

type ModifyMemberStorage struct {
	ID           uuid.UUID `json:"id" binding:"required"`
	StorageLimit *int64    `json:"storageLimit"`
}

type FamilyMemberResponse struct {
	Members []FamilyMember `json:"members" binding:"required"`
	// The family admin's plan storage, excluding bonuses and add-ons.
	Storage    int64 `json:"storage" binding:"required"`
	ExpiryTime int64 `json:"expiryTime" binding:"required"`

	AdminBonus int64 `json:"adminBonus" binding:"required"`
}

type UserUsageWithSubData struct {
	UserID          int64
	StorageConsumed int64
	ExpiryTime      int64
	Storage         int64
	Email           *string
}
