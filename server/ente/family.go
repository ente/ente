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
	// This information should not be sent back in the response if the membership status is `INVITED`
	Usage        int64 `json:"usage"`
	IsAdmin      bool  `json:"isAdmin"`
	MemberUserID int64 `json:"-"` // for internal use only, ignore from json response
	AdminUserID  int64 `json:"-"` // for internal use only, ignore from json response
}

type ModifyMemberStorage struct {
	ID           uuid.UUID `json:"id" binding:"required"`
	StorageLimit *int64    `json:"storageLimit"`
}

type FamilyMemberResponse struct {
	Members []FamilyMember `json:"members" binding:"required"`
	// Family admin subscription storage capacity. This excludes add-on and any other bonus storage
	Storage int64 `json:"storage" binding:"required"`
	// Family admin subscription expiry time
	ExpiryTime int64 `json:"expiryTime" binding:"required"`

	AdminBonus int64 `json:"adminBonus" binding:"required"`
}

type UserUsageWithSubData struct {
	UserID int64
	// StorageConsumed by the current member.
	// This information should not be sent back in the response if the membership status is `INVITED`
	StorageConsumed int64
	// ExpiryTime of member's current subscription plan
	ExpiryTime int64
	// Storage indicates storage capacity based on member's current subscription plan
	Storage int64
	// Email of the member. It will be populated on need basis
	Email *string
}
