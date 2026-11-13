package storagebonus

type BonusType string

const (
	Referral BonusType = "REFERRAL"
	SignUp   BonusType = "SIGN_UP"

	AddOnSupport   BonusType = "ADD_ON_SUPPORT"
	AddOnNonProfit BonusType = "ADD_ON_NON_PROFIT"
	AddOnBf2023    BonusType = "ADD_ON_BF_2023"
	AddOnBf2024    BonusType = "ADD_ON_BF_2024"
)

var PaidAddOnTypes = []BonusType{AddOnSupport, AddOnNonProfit, AddOnBf2023, AddOnBf2024}

func (t BonusType) ExtendsExpiry() bool {
	switch t {
	case AddOnSupport, AddOnNonProfit, AddOnBf2023, AddOnBf2024:
		return true
	case Referral, SignUp:
		return false
	default:
		return false
	}
}

func BonusFromType(bonusType string) BonusType {
	switch bonusType {
	case "REFERRAL":
		return Referral
	case "SIGN_UP":
		return SignUp
	case "ADD_ON_SUPPORT":
		return AddOnSupport
	case "ADD_ON_NON_PROFIT":
		return AddOnNonProfit
	case "ADD_ON_BF_2023":
		return AddOnBf2023
	case "ADD_ON_BF_2024":
		return AddOnBf2024
	default:
		return ""
	}
}

// RestrictToDoublingStorage returns true if the bonus type restricts the doubling of storage.
// This indicates, the usable bonus storage should not exceed the current plan storage.
// Note: Current plan storage includes both base subscription and storage bonus that can ExtendsExpiry
func (t BonusType) RestrictToDoublingStorage() bool {
	switch t {
	case Referral, SignUp:
		return true
	case AddOnSupport, AddOnNonProfit, AddOnBf2023, AddOnBf2024:
		return false
	default:
		return true
	}
}

type RevokeReason string

const (
	Fraud        RevokeReason = "FRAUD"
	Expired      RevokeReason = "EXPIRED"
	Discontinued RevokeReason = "DISCONTINUED"
)

type StorageBonus struct {
	UserID    int64     `json:"-"`
	Storage   int64     `json:"storage"`
	Type      BonusType `json:"type"`
	CreatedAt int64     `json:"createdAt"`
	UpdatedAt int64     `json:"-"`
	// Zero means no expiry.
	ValidTill    int64         `json:"validTill"`
	RevokeReason *RevokeReason `json:"-"`
	IsRevoked    bool          `json:"isRevoked"`
}

type ActiveStorageBonus struct {
	StorageBonuses []StorageBonus `json:"storageBonuses"`
}

func (a *ActiveStorageBonus) GetMaxExpiry() int64 {
	if a == nil {
		return 0
	}
	maxExpiry := int64(0)
	for _, bonus := range a.StorageBonuses {
		if bonus.Type.ExtendsExpiry() && bonus.ValidTill > maxExpiry {
			maxExpiry = bonus.ValidTill
		}
	}
	return maxExpiry
}

func (a *ActiveStorageBonus) GetReferralBonus() int64 {
	if a == nil {
		return 0
	}
	referralBonus := int64(0)
	for _, bonus := range a.StorageBonuses {
		if bonus.Type.RestrictToDoublingStorage() {
			referralBonus += bonus.Storage
		}
	}
	return referralBonus
}

func (a *ActiveStorageBonus) GetAddonStorage() int64 {
	if a == nil {
		return 0
	}
	addonStorage := int64(0)
	for _, bonus := range a.StorageBonuses {
		if !bonus.Type.RestrictToDoublingStorage() {
			addonStorage += bonus.Storage
		}
	}
	return addonStorage
}

func (a *ActiveStorageBonus) GetUsableBonus(subStorage int64) int64 {
	refBonus := a.GetReferralBonus()
	totalSubAndAddOnStorage := a.GetAddonStorage() + subStorage
	if refBonus > totalSubAndAddOnStorage {
		refBonus = totalSubAndAddOnStorage
	}
	return a.GetAddonStorage() + refBonus
}

type GetBonusResult struct {
	StorageBonuses []StorageBonus
}
