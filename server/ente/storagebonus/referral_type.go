package storagebonus

import (
	"fmt"
)

type PlanType string

const (
	TenGbOnUpgrade PlanType = "10_GB_ON_UPGRADE"
)

func (c PlanType) SignUpInviteeBonus() int64 {
	switch c {
	case TenGbOnUpgrade:
		return 10 * 1024 * 1024 * 1024
	default:
		panic(fmt.Sprintf("SignUpInviteeBonus value not configured for %s", c))
	}
}

func (c PlanType) SignUpInvitorBonus() int64 {
	switch c {
	case TenGbOnUpgrade:
		return 0
	default:
		panic("unsupported plan type")
	}
}

func (c PlanType) InvitorBonusOnInviteeUpgrade() int64 {
	switch c {
	case TenGbOnUpgrade:
		return 10 * 1024 * 1024 * 1024
	default:
		panic("unsupported plan type")
	}
}
