package controller

import (
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/billing"
)

func TestShouldSkipVerifiedSubscriptionReplacement(t *testing.T) {
	now := int64(10_000_000_000_000)
	appStoreGrace := billing.ProviderToExpiryGracePeriodMap[ente.AppStore]
	paid := func(provider ente.PaymentProvider, transactionID string, expiry int64) ente.Subscription {
		return ente.Subscription{
			ProductID:             "paid",
			PaymentProvider:       provider,
			OriginalTransactionID: transactionID,
			ExpiryTime:            expiry,
		}
	}

	tests := []struct {
		name     string
		current  ente.Subscription
		verified ente.Subscription
		want     bool
	}{
		{
			name:     "rejects receipt beyond provider grace",
			current:  paid(ente.Stripe, "stripe", now+15),
			verified: paid(ente.AppStore, "apple", now-appStoreGrace-1),
			want:     true,
		},
		{
			name:     "accepts receipt within provider grace for free account",
			current:  ente.Subscription{ProductID: ente.FreePlanProductID},
			verified: paid(ente.AppStore, "apple", now-appStoreGrace+1),
		},
		{
			name:     "accepts cross-provider switch within provider grace",
			current:  paid(ente.Stripe, "stripe", now+45),
			verified: paid(ente.AppStore, "apple", now-appStoreGrace+1),
		},
		{
			name:     "rejects older Play purchase with a different token",
			current:  paid(ente.PlayStore, "new-token", now+45),
			verified: paid(ente.PlayStore, "old-token", now+30),
			want:     true,
		},
		{
			name:     "accepts newer Play purchase with a different token",
			current:  paid(ente.PlayStore, "old-token", now+30),
			verified: paid(ente.PlayStore, "new-token", now+45),
		},
		{
			name:     "rejects older version of the same subscription",
			current:  paid(ente.AppStore, "apple", now+45),
			verified: paid(ente.AppStore, "apple", now+30),
			want:     true,
		},
		{
			name: "accepts App Store product change with earlier expiry",
			current: ente.Subscription{
				ProductID: "old", PaymentProvider: ente.AppStore, OriginalTransactionID: "apple", ExpiryTime: now + 45,
			},
			verified: ente.Subscription{
				ProductID: "new", PaymentProvider: ente.AppStore, OriginalTransactionID: "apple", ExpiryTime: now + 30,
			},
		},
		{
			name: "accepts Play Store product change with earlier expiry",
			current: ente.Subscription{
				ProductID: "old", PaymentProvider: ente.PlayStore, OriginalTransactionID: "old-token", ExpiryTime: now + 45,
			},
			verified: ente.Subscription{
				ProductID: "new", PaymentProvider: ente.PlayStore, OriginalTransactionID: "new-token", ExpiryTime: now + 30,
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := shouldSkipVerifiedSubscriptionReplacement(test.current, test.verified, now); got != test.want {
				t.Fatalf("shouldSkipVerifiedSubscriptionReplacement() = %t, want %t", got, test.want)
			}
		})
	}
}
