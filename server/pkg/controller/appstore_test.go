package controller

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/awa/go-iap/appstore"
	"github.com/ente/museum/ente"
)

func TestGetCurrentAppStoreTransactionUsesLatestPurchase(t *testing.T) {
	transaction, err := getCurrentAppStoreTransaction([]appstore.InApp{
		appStoreReceipt("large", "old", "original", "100", "500", true, false),
		appStoreReceipt("small", "new", "original", "200", "400", false, false),
	})
	if err != nil {
		t.Fatal(err)
	}
	if transaction.receiptInfo.ProductID != "small" {
		t.Fatalf("product ID = %q, want small", transaction.receiptInfo.ProductID)
	}
	if transaction.expiryTimeMicros != 400_000 {
		t.Fatalf("expiry time in microseconds = %d, want 400000", transaction.expiryTimeMicros)
	}
}

func TestGetCurrentAppStoreTransactionIgnoresAmbiguousOlderPurchase(t *testing.T) {
	transaction, err := getCurrentAppStoreTransaction([]appstore.InApp{
		appStoreReceipt("old", "old-first", "original", "100", "300", false, false),
		appStoreReceipt("old", "old-second", "original", "100", "300", false, false),
		appStoreReceipt("current", "current", "original", "200", "400", false, false),
	})
	if err != nil {
		t.Fatal(err)
	}
	if transaction.receiptInfo.TransactionID != "current" {
		t.Fatalf("transaction ID = %q, want current", transaction.receiptInfo.TransactionID)
	}
}

func TestGetCurrentAppStoreTransactionRejectsInvalidCurrentPurchase(t *testing.T) {
	tests := []struct {
		name     string
		receipts []appstore.InApp
	}{
		{name: "empty"},
		{
			name:     "upgraded",
			receipts: []appstore.InApp{appStoreReceipt("small", "new", "original", "200", "400", true, false)},
		},
		{
			name:     "missing product",
			receipts: []appstore.InApp{appStoreReceipt("", "new", "original", "200", "400", false, false)},
		},
		{
			name:     "missing transaction",
			receipts: []appstore.InApp{appStoreReceipt("small", "", "original", "200", "400", false, false)},
		},
		{
			name:     "missing original transaction",
			receipts: []appstore.InApp{appStoreReceipt("small", "new", "", "200", "400", false, false)},
		},
		{
			name:     "invalid purchase time",
			receipts: []appstore.InApp{appStoreReceipt("small", "new", "original", "invalid", "400", false, false)},
		},
		{
			name:     "invalid expiry time",
			receipts: []appstore.InApp{appStoreReceipt("small", "new", "original", "200", "invalid", false, false)},
		},
		{
			name: "ambiguous purchase time",
			receipts: []appstore.InApp{
				appStoreReceipt("small", "first", "original", "200", "400", false, false),
				appStoreReceipt("small", "second", "original", "200", "400", false, false),
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if _, err := getCurrentAppStoreTransaction(test.receipts); err == nil {
				t.Fatal("getCurrentAppStoreTransaction() succeeded, want error")
			}
		})
	}
}

func TestGetAppStoreStorageUsesAllConfiguredAccountsAndCountries(t *testing.T) {
	controller := &AppStoreController{
		BillingPlansPerAccount: ente.BillingPlansPerAccount{
			ente.StripeUS: {"EU": {{IOSID: "current", Storage: 1000}}},
			ente.StripeIN: {"US": {{IOSID: "legacy", Storage: 100}}},
		},
	}

	storage, err := controller.getAppStoreStorage("legacy")
	if err != nil {
		t.Fatal(err)
	}
	if storage != 100 {
		t.Fatalf("storage = %d, want 100", storage)
	}
}

func TestGetAppStoreStorageRejectsInvalidConfiguration(t *testing.T) {
	tests := []struct {
		name       string
		controller *AppStoreController
		productID  string
	}{
		{
			name:       "unknown product",
			controller: appStoreControllerWithPlans(ente.BillingPlan{IOSID: "known", Storage: 100}),
			productID:  "unknown",
		},
		{
			name: "inconsistent storage",
			controller: &AppStoreController{BillingPlansPerAccount: ente.BillingPlansPerAccount{
				ente.StripeUS: {"EU": {{IOSID: "product", Storage: 100}}},
				ente.StripeIN: {"US": {{IOSID: "product", Storage: 1000}}},
			}},
			productID: "product",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if _, err := test.controller.getAppStoreStorage(test.productID); err == nil {
				t.Fatal("getAppStoreStorage() succeeded, want error")
			}
		})
	}
}

func TestGetVerifiedAppStoreSubscriptionUsesReceiptProduct(t *testing.T) {
	controller, request := appStoreVerificationController(t,
		[]appstore.InApp{appStoreReceipt("small", "new", "original", "200", "400", false, false)},
		ente.BillingPlan{IOSID: "small", Storage: 100},
		ente.BillingPlan{IOSID: "large", Storage: 1000},
	)

	subscription, err := controller.GetVerifiedSubscription(1, "large", "receipt")
	if err != nil {
		t.Fatal(err)
	}
	if subscription.ProductID != "small" {
		t.Fatalf("product ID = %q, want small", subscription.ProductID)
	}
	if subscription.Storage != 100 {
		t.Fatalf("storage = %d, want 100", subscription.Storage)
	}
	if !request.ExcludeOldTransactions {
		t.Fatal("exclude-old-transactions = false, want true")
	}
}

func TestGetVerifiedAppStoreSubscriptionRejectsCancelledEntitlement(t *testing.T) {
	controller, _ := appStoreVerificationController(t,
		[]appstore.InApp{appStoreReceipt("small", "new", "original", "200", "400", false, true)},
		ente.BillingPlan{IOSID: "small", Storage: 100},
	)

	if _, err := controller.GetVerifiedSubscription(1, "small", "receipt"); err == nil {
		t.Fatal("GetVerifiedSubscription() succeeded, want error")
	}
}

func appStoreControllerWithPlans(plans ...ente.BillingPlan) *AppStoreController {
	return &AppStoreController{
		BillingPlansPerAccount: ente.BillingPlansPerAccount{
			ente.StripeUS: {"EU": plans},
		},
	}
}

func appStoreVerificationController(t *testing.T, receipts []appstore.InApp, plans ...ente.BillingPlan) (*AppStoreController, *appstore.IAPRequest) {
	t.Helper()
	request := &appstore.IAPRequest{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewDecoder(r.Body).Decode(request); err != nil {
			t.Error(err)
		}
		if err := json.NewEncoder(w).Encode(map[string]any{
			"status":              0,
			"environment":         appstore.Production,
			"latest_receipt_info": receipts,
		}); err != nil {
			t.Error(err)
		}
	}))
	t.Cleanup(server.Close)

	client := appstore.NewWithClient(server.Client())
	client.ProductionURL = server.URL
	client.SandboxURL = server.URL
	controller := appStoreControllerWithPlans(plans...)
	controller.AppStoreClient = *client
	return controller, request
}

func appStoreReceipt(
	productID string,
	transactionID string,
	originalTransactionID string,
	purchaseTimeMillis string,
	expiryTimeMillis string,
	isUpgraded bool,
	isCancelled bool,
) appstore.InApp {
	receipt := appstore.InApp{
		ProductID:             productID,
		TransactionID:         transactionID,
		OriginalTransactionID: originalTransactionID,
		PurchaseDate:          appstore.PurchaseDate{PurchaseDateMS: purchaseTimeMillis},
		ExpiresDate:           appstore.ExpiresDate{ExpiresDateMS: expiryTimeMillis},
	}
	if isUpgraded {
		receipt.IsUpgraded = "true"
	}
	if isCancelled {
		receipt.CancellationDateMS = "300"
	}
	return receipt
}
