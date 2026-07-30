package ente

import (
	"database/sql/driver"
	"encoding/json"

	"github.com/ente/stacktrace"
	"github.com/stripe/stripe-go/v72"
	"github.com/stripe/stripe-go/v72/client"
)

const (
	// FreePlanStorage is the amount of storage in free plan
	FreePlanStorage int64 = 10 * 1024 * 1024 * 1024
	// FreePlanProductID is the product ID of free plan
	FreePlanProductID = "free"
	// FreePlanTransactionID is the dummy transaction ID for the free plan
	FreePlanTransactionID = "none"
	// TrialPeriodDuration is the duration (in years) of the free trial
	TrialPeriodDuration = 100
	// TrialPeriod is the unit for the duration of the free trial
	TrialPeriod = "days"

	// PeriodYear is the unit for the duration of the yearly plan
	PeriodYear = "year"

	// PeriodMonth is the unit for the duration of the monthly plan
	PeriodMonth = "month"

	Period3Years = "3"

	Period5Years = "5"

	Period10Years = "10"

	// FamilyPlanProductID is the product ID of family (internal employees & their friends & family) plan
	FamilyPlanProductID = "family"

	// StripeSignature is the header send by the stripe webhook to verify authenticity
	StripeSignature = "Stripe-Signature"

	// OnHoldTemplate is the template for the email
	// that is to be sent out when an account enters the hold stage
	OnHoldTemplate = "on_hold.html"

	// AccountOnHoldEmailSubject is the subject of account on hold email
	AccountOnHoldEmailSubject = "Ente account on hold"

	// Template for the email we send out when the user's subscription ends,
	// either because the user cancelled their subscription, or because it
	// expired.
	SubscriptionEndedEmailTemplate = "subscription_ended.html"

	// Subject for `SubscriptionEndedEmailTemplate`.
	SubscriptionEndedEmailSubject = "Your subscription to Ente Photos has ended"
)

// PaymentProvider represents the payment provider via which a purchase was made
type PaymentProvider string

const (
	// PlayStore was the payment provider
	PlayStore PaymentProvider = "playstore"
	// AppStore was the payment provider
	AppStore PaymentProvider = "appstore"
	// Stripe was the payment provider
	Stripe PaymentProvider = "stripe"
	// Paypal was the payment provider
	Paypal PaymentProvider = "paypal"
	// BitPay was the payment provider
	BitPay PaymentProvider = "bitpay"
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

// AndroidNotification represents a notification received from PlayStore
type AndroidNotification struct {
	Message      AndroidNotificationMessage `json:"message"`
	Subscription string                     `json:"subscription"`
}

// AndroidNotificationMessage represents the message within the notification received from
// PlayStore
type AndroidNotificationMessage struct {
	Attributes map[string]string `json:"attributes"`
	Data       string            `json:"data"`
	MessageID  string            `json:"messageId"`
}

// BillingPlan represents a billing plan
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

// Subscription represents a user's subscription to a billing plan
type Subscription struct {
	ID     int64 `json:"id"`
	UserID int64 `json:"userID"`
	// Identifier of the product on respective stores that the user has subscribed to
	ProductID string `json:"productID"`
	Storage   int64  `json:"storage"`
	// LinkedPurchaseToken on PlayStore , OriginalTransactionID on AppStore and SubscriptionID on Stripe
	OriginalTransactionID string                 `json:"originalTransactionID"`
	ExpiryTime            int64                  `json:"expiryTime"`
	UpgradedAt            int64                  `json:"upgradedAt,omitempty"`
	PaymentProvider       PaymentProvider        `json:"paymentProvider"`
	Attributes            SubscriptionAttributes `json:"attributes"`
	Price                 string                 `json:"price"`
	Period                string                 `json:"period"`
}

// SubscriptionAttributes represents a subscription's paymentProvider specific attributes
type SubscriptionAttributes struct {
	// IsCancelled represents if subscription's renewal have been cancelled
	IsCancelled bool `json:"isCancelled,omitempty"`
	// CustomerID represents the stripe customerID
	CustomerID string `json:"customerID,omitempty"`
	// LatestVerificationData is the the latestTransactionReceipt received
	LatestVerificationData string `json:"latestVerificationData,omitempty"`
	// StripeAccountCountry is the identifier for the account in which the subscription is created.
	StripeAccountCountry StripeAccountCountry `json:"stripeAccountCountry,omitempty"`
}

// Value implements the driver.Valuer interface. This method
// simply returns the JSON-encoded representation of the struct.
func (ca SubscriptionAttributes) Value() (driver.Value, error) {
	return json.Marshal(ca)
}

// Scan implements the sql.Scanner interface. This method
// simply decodes a JSON-encoded value into the struct fields.
func (ca *SubscriptionAttributes) Scan(value interface{}) error {
	b, ok := value.([]byte)
	if !ok {
		return stacktrace.NewError("type assertion to []byte failed")
	}

	return json.Unmarshal(b, &ca)
}

// SubscriptionVerificationRequest represents a request to verify a subscription done via a paymentProvider
type SubscriptionVerificationRequest struct {
	PaymentProvider  PaymentProvider `json:"paymentProvider"`
	ProductID        string          `json:"productID"`
	VerificationData string          `json:"verificationData"`
}

// StripeUpdateRequest represents a request to modify the stripe subscription
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
