package ente

import (
	"database/sql/driver"
	"encoding/json"

	"github.com/ente/stacktrace"
	"github.com/stripe/stripe-go/v72"
	"github.com/stripe/stripe-go/v72/client"
)

const (
	FreePlanStorage       int64 = 10 * 1024 * 1024 * 1024
	FreePlanProductID           = "free"
	FreePlanTransactionID       = "none"
	TrialPeriodDuration         = 100
	TrialPeriod                 = "days"

	PeriodYear = "year"

	PeriodMonth = "month"

	Period3Years = "3"

	Period5Years = "5"

	Period10Years = "10"

	FamilyPlanProductID = "family"

	StripeSignature = "Stripe-Signature"

	OnHoldTemplate = "on_hold.html"

	AccountOnHoldEmailSubject = "Ente account on hold"

	SubscriptionEndedEmailTemplate = "subscription_ended.html"

	SubscriptionEndedEmailSubject = "Your subscription to Ente Photos has ended"
)

type PaymentProvider string

const (
	PlayStore PaymentProvider = "playstore"
	AppStore  PaymentProvider = "appstore"
	Stripe    PaymentProvider = "stripe"
	Paypal    PaymentProvider = "paypal"
	BitPay    PaymentProvider = "bitpay"
)

type StripeAccountCountry string

type BillingPlansPerCountry map[string][]BillingPlan

type BillingPlansPerAccount map[StripeAccountCountry]BillingPlansPerCountry

type StripeClientPerAccount map[StripeAccountCountry]*client.API

const (
	StripeIN StripeAccountCountry = "IN"
	StripeUS StripeAccountCountry = "US"
)

const DefaultStripeAccountCountry = StripeUS

type AndroidNotification struct {
	Message      AndroidNotificationMessage `json:"message"`
	Subscription string                     `json:"subscription"`
}

type AndroidNotificationMessage struct {
	Attributes map[string]string `json:"attributes"`
	Data       string            `json:"data"`
	MessageID  string            `json:"messageId"`
}

type BillingPlan struct {
	ID        string `json:"id"`
	AndroidID string `json:"androidID"`
	IOSID     string `json:"iosID"`
	StripeID  string `json:"stripeID"`
	Storage   int64  `json:"storage"`
	Price     string `json:"price"`
	Period    string `json:"period"`
}

type FreePlan struct {
	Storage  int64  `json:"storage"`
	Duration int    `json:"duration"`
	Period   string `json:"period"`
}

type Subscription struct {
	ID        int64  `json:"id"`
	UserID    int64  `json:"userID"`
	ProductID string `json:"productID"`
	Storage   int64  `json:"storage"`
	// Play Store linked purchase token, App Store original transaction ID, or
	// Stripe subscription ID.
	OriginalTransactionID string                 `json:"originalTransactionID"`
	ExpiryTime            int64                  `json:"expiryTime"`
	UpgradedAt            int64                  `json:"upgradedAt,omitempty"`
	PaymentProvider       PaymentProvider        `json:"paymentProvider"`
	Attributes            SubscriptionAttributes `json:"attributes"`
	Price                 string                 `json:"price"`
	Period                string                 `json:"period"`
}

type SubscriptionAttributes struct {
	IsCancelled            bool                 `json:"isCancelled,omitempty"`
	CustomerID             string               `json:"customerID,omitempty"`
	LatestVerificationData string               `json:"latestVerificationData,omitempty"`
	StripeAccountCountry   StripeAccountCountry `json:"stripeAccountCountry,omitempty"`
}

func (ca SubscriptionAttributes) Value() (driver.Value, error) {
	return json.Marshal(ca)
}

func (ca *SubscriptionAttributes) Scan(value interface{}) error {
	b, ok := value.([]byte)
	if !ok {
		return stacktrace.NewError("type assertion to []byte failed")
	}

	return json.Unmarshal(b, &ca)
}

type SubscriptionVerificationRequest struct {
	PaymentProvider  PaymentProvider `json:"paymentProvider"`
	ProductID        string          `json:"productID"`
	VerificationData string          `json:"verificationData"`
}

type StripeUpdateRequest struct {
	ProductID string `json:"productID"`
}
type SubscriptionUpdateResponse struct {
	Status       string `json:"status"`
	ClientSecret string `json:"clientSecret"`
}

type StripeEventLog struct {
	UserID             int64
	StripeSubscription stripe.Subscription
	Event              stripe.Event
}
