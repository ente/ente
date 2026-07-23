package storagebonus

import (
	"slices"
	"testing"
)

func TestAddOnNonProfitBonusProperties(t *testing.T) {
	if got := BonusFromType("ADD_ON_NON_PROFIT"); got != AddOnNonProfit {
		t.Fatalf("expected ADD_ON_NON_PROFIT to map to AddOnNonProfit, got %q", got)
	}
	if !AddOnNonProfit.ExtendsExpiry() {
		t.Fatal("expected ADD_ON_NON_PROFIT to extend expiry")
	}
	if AddOnNonProfit.RestrictToDoublingStorage() {
		t.Fatal("expected ADD_ON_NON_PROFIT to behave like an add-on bonus")
	}

	if !slices.Contains(PaidAddOnTypes, AddOnNonProfit) {
		t.Fatal("expected ADD_ON_NON_PROFIT to be treated as a paid add-on type")
	}
}
