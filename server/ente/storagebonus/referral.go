package storagebonus

type Tracking struct {
	Invitor   int64
	Invitee   int64
	CreatedAt int64

	PlanType PlanType
}

type UserReferralPlanStat struct {
	PlanType      PlanType `json:"planType"`
	TotalCount    int      `json:"totalCount"`
	UpgradedCount int      `json:"upgradedCount"`
}

type UpdateReferralCodeRequest struct {
	Code string `json:"code" binding:"required"`
}

type PlanInfo struct {
	IsEnabled               bool     `json:"isEnabled"`
	PlanType                PlanType `json:"planType"`
	StorageInGB             int64    `json:"storageInGB"`
	MaxClaimableStorageInGB int64    `json:"maxClaimableStorageInGB"`
}

type GetStorageBonusDetailResponse struct {
	ReferralStats   []UserReferralPlanStat `json:"referralStats"`
	Bonuses         []StorageBonus         `json:"bonuses"`
	RefCount        int                    `json:"refCount"`
	RefUpgradeCount int                    `json:"refUpgradeCount"`
	HasAppliedCode  bool                   `json:"hasAppliedCode"`
}

type GetUserReferralView struct {
	PlanInfo                    PlanInfo `json:"planInfo"`
	Code                        *string  `json:"code"`
	EnableApplyCode             bool     `json:"enableApplyCode"`
	HasAppliedCode              bool     `json:"hasAppliedCode"`
	ClaimedStorage              int64    `json:"claimedStorage"`
	IsFamilyMember              bool     `json:"isFamilyMember"`
	CodeChangeAttempts          int      `json:"codeChangeAttempts"`
	RemainingCodeChangeAttempts int      `json:"remainingCodeChangeAttempts"`
}
