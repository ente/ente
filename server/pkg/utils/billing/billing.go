package billing

import (
	"encoding/json"
	"os"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/config"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/sirupsen/logrus"
	"github.com/spf13/viper"
	"github.com/stripe/stripe-go/v72/client"
)

var ProviderToExpiryGracePeriodMap = map[ente.PaymentProvider]int64{
	ente.AppStore:  time.MicroSecondsInOneHour * 120, // 5 days
	ente.Paypal:    time.MicroSecondsInOneHour * 120,
	ente.PlayStore: time.MicroSecondsInOneHour * 120,
	ente.Stripe:    time.MicroSecondsInOneHour * 336, // 14 days
}

var CountriesInEU = []string{
	"AT",
	"BE",
	"BG",
	"CY",
	"CZ",
	"DE",
	"DK",
	"EE",
	"ES",
	"FI",
	"FR",
	"GR",
	"HR",
	"HU",
	"IE",
	"IT",
	"LT",
	"LU",
	"LV",
	"MT",
	"NL",
	"PL",
	"PT",
	"RO",
	"SE",
	"SI",
	"SK",
}

// GetPlans returns current billing plans
func GetPlans() ente.BillingPlansPerAccount {
	var plans = make(ente.BillingPlansPerAccount)
	plans[ente.StripeIN] = getPlansIN()
	plans[ente.StripeUS] = getPlansUS()
	return plans
}

// GetStripeClients returns stripe clients for all accounts
func GetStripeClients() ente.StripeClientPerAccount {
	stripeClients := make(ente.StripeClientPerAccount)
	stripeClients[ente.StripeIN] = getStripeClient(viper.GetString("stripe.in.key"))
	stripeClients[ente.StripeUS] = getStripeClient(viper.GetString("stripe.us.key"))
	return stripeClients
}

func getPlansUS() ente.BillingPlansPerCountry {
	fileName := "us.json"
	if config.IsLocalEnvironment() {
		fileName = "us-testing.json"
	}
	return parsePricingFile(fileName)
}

func getPlansIN() ente.BillingPlansPerCountry {
	fileName := "in.json"
	if config.IsLocalEnvironment() {
		fileName = "in-testing.json"
	}
	return parsePricingFile(fileName)
}

func parsePricingFile(fileName string) ente.BillingPlansPerCountry {
	filePath, err := config.BillingConfigFilePath(fileName)
	if err != nil {
		logrus.Fatalf("Error getting billing config file: %v", err)
	}
	data, err := os.ReadFile(filePath)
	if err != nil {
		logrus.Errorf("Skipping payment configuration, pricing data unavailable in config: %v\n", err)
		return nil
	}

	var plansPerCountry ente.BillingPlansPerCountry
	err = json.Unmarshal(data, &plansPerCountry)
	if err != nil {
		logrus.Errorf("Error un-marshalling JSON: %v\n", err)
		return nil
	}
	return plansPerCountry
}

// GetFreeSubscription return a free subscription for a new signed up user
func GetFreeSubscription(userID int64) ente.Subscription {
	return ente.Subscription{
		UserID:                userID,
		ProductID:             ente.FreePlanProductID,
		OriginalTransactionID: ente.FreePlanTransactionID,
		Storage:               ente.FreePlanStorage,
		ExpiryTime:            time.NYearsFromNow(ente.TrialPeriodDuration),
	}
}

func GetFreePlan() ente.FreePlan {
	return ente.FreePlan{
		Storage:  ente.FreePlanStorage,
		Period:   ente.PeriodYear,
		Duration: ente.TrialPeriodDuration,
	}
}

func GetActivePlanIDs() []string {
	return []string{
		"50gb_monthly_v4",
		"200gb_monthly_v4",
		"1000gb_monthly_v4",
		"2000gb_monthly_v4",
		"50gb_yearly_v4",
		"200gb_yearly_v4",
		"1000gb_yearly_v4",
		"2000gb_yearly_v4",
	}
}

func IsActivePaidPlan(subscription ente.Subscription) bool {
	return subscription.ProductID != ente.FreePlanProductID && subscription.ExpiryTime > time.Microseconds()
}

func GetDefaultPlans(plans ente.BillingPlansPerAccount) ente.BillingPlansPerCountry {
	if ente.DefaultStripeAccountCountry == ente.StripeIN {
		return plans[ente.StripeIN]
	} else {
		return plans[ente.StripeUS]
	}
}

func GetDefaultPlanCountry() string {
	return "US"
}

func getStripeClient(apiKey string) *client.API {
	stripeClient := &client.API{}
	stripeClient.Init(apiKey, nil)
	return stripeClient
}
