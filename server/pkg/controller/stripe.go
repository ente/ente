package controller

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/ente/museum/pkg/controller/commonbilling"

	"github.com/ente/museum/pkg/controller/discord"
	"github.com/ente/museum/pkg/controller/offer"
	"github.com/ente/museum/pkg/repo/storagebonus"

	"github.com/ente/museum/ente"
	emailCtrl "github.com/ente/museum/pkg/controller/email"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/billing"
	"github.com/ente/museum/pkg/utils/email"
	timeUtil "github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/viper"
	"github.com/stripe/stripe-go/v72"
	"github.com/stripe/stripe-go/v72/client"
	"github.com/stripe/stripe-go/v72/webhook"
	"golang.org/x/text/currency"
)

// StripeController provides abstractions for handling billing on Stripe
type StripeController struct {
	StripeClients          ente.StripeClientPerAccount
	BillingPlansPerAccount ente.BillingPlansPerAccount
	BillingRepo            *repo.BillingRepository
	FileRepo               *repo.FileRepository
	UserRepo               *repo.UserRepository
	StorageBonusRepo       *storagebonus.Repository
	DiscordController      *discord.DiscordController
	EmailNotificationCtrl  *emailCtrl.EmailNotificationController
	OfferController        *offer.OfferController
	CommonBillCtrl         *commonbilling.Controller
}

const BufferPeriodOnPaymentFailureInDays = 7

// Return a new instance of StripeController
func NewStripeController(plans ente.BillingPlansPerAccount, stripeClients ente.StripeClientPerAccount, billingRepo *repo.BillingRepository, fileRepo *repo.FileRepository, userRepo *repo.UserRepository, storageBonusRepo *storagebonus.Repository, discordController *discord.DiscordController, emailNotificationController *emailCtrl.EmailNotificationController, offerController *offer.OfferController, commonBillCtrl *commonbilling.Controller) *StripeController {
	return &StripeController{
		StripeClients:          stripeClients,
		BillingRepo:            billingRepo,
		FileRepo:               fileRepo,
		UserRepo:               userRepo,
		BillingPlansPerAccount: plans,
		StorageBonusRepo:       storageBonusRepo,
		DiscordController:      discordController,
		EmailNotificationCtrl:  emailNotificationController,
		OfferController:        offerController,
		CommonBillCtrl:         commonBillCtrl,
	}
}

// GetCheckoutSession handles the creation of stripe checkout session for subscription purchase
func (c *StripeController) GetCheckoutSession(productID string, userID int64, redirectRootURL string) (string, error) {
	if productID == "" {
		return "", stacktrace.Propagate(ente.ErrBadRequest, "")
	}
	subscription, err := c.BillingRepo.GetUserSubscription(userID)
	if err != nil {
		// error sql.ErrNoRows not possible as user must at least have a free subscription
		return "", stacktrace.Propagate(err, "")
	}
	hasActivePaidSubscription := billing.IsActivePaidPlan(subscription)
	hasStripeSubscription := subscription.PaymentProvider == ente.Stripe
	if hasActivePaidSubscription {
		if hasStripeSubscription {
			return "", stacktrace.Propagate(ente.ErrBadRequest, "")
		} else if !subscription.Attributes.IsCancelled {
			return "", stacktrace.Propagate(ente.ErrBadRequest, "")
		}
	}
	if hasStripeSubscription {
		client := c.StripeClients[subscription.Attributes.StripeAccountCountry]
		stripeSubscription, err := client.Subscriptions.Get(subscription.OriginalTransactionID, nil)
		if err != nil {
			return "", stacktrace.Propagate(err, "")
		}
		if stripeSubscription.Status != stripe.SubscriptionStatusCanceled {
			return "", stacktrace.Propagate(ente.ErrBadRequest, "")
		}
	}
	stripeSuccessURL := redirectRootURL + viper.GetString("stripe.path.success")
	stripeCancelURL := redirectRootURL + viper.GetString("stripe.path.cancel")
	allowPromotionCodes := true
	params := &stripe.CheckoutSessionParams{
		ClientReferenceID: stripe.String(strconv.FormatInt(userID, 10)),
		SuccessURL:        stripe.String(stripeSuccessURL),
		CancelURL:         stripe.String(stripeCancelURL),
		Mode:              stripe.String(string(stripe.CheckoutSessionModeSubscription)),
		LineItems: []*stripe.CheckoutSessionLineItemParams{
			{
				Price:    stripe.String(productID),
				Quantity: stripe.Int64(1),
			},
		},
		AllowPromotionCodes: &allowPromotionCodes,
	}
	var stripeClient *client.API
	if subscription.PaymentProvider == ente.Stripe {
		stripeClient = c.StripeClients[subscription.Attributes.StripeAccountCountry]
		// attach the subscription to existing customerID
		params.Customer = stripe.String(subscription.Attributes.CustomerID)
	} else {
		stripeClient = c.StripeClients[ente.DefaultStripeAccountCountry]
		user, err := c.UserRepo.Get(userID)
		if err != nil {
			return "", stacktrace.Propagate(err, "")
		}
		// attach user's emailID to the checkout session and subsequent subscription bought
		params.CustomerEmail = stripe.String(user.Email)
	}

	s, err := stripeClient.CheckoutSessions.New(params)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	return s.ID, nil
}

// GetVerifiedSubscription verifies and returns the verified subscription
func (c *StripeController) GetVerifiedSubscription(userID int64, sessionID string) (ente.Subscription, error) {
	var stripeSubscription stripe.Subscription
	var err error
	if sessionID != "" {
		log.Info("Received session ID: " + sessionID)
		// Get verified subscription request was received from success redirect page
		stripeSubscription, err = c.getStripeSubscriptionFromSession(userID, sessionID)
	} else {
		log.Info("Did not receive a session ID")
		// Get verified subscription request for a subscription update
		stripeSubscription, err = c.getUserStripeSubscription(userID)
	}
	if err != nil {
		return ente.Subscription{}, stacktrace.Propagate(err, "")
	}
	log.Info("Received stripe subscription with ID: " + stripeSubscription.ID)
	subscription, err := c.getEnteSubscriptionFromStripeSubscription(userID, stripeSubscription)
	if err != nil {
		return ente.Subscription{}, stacktrace.Propagate(err, "")
	}
	log.Info("Returning ente subscription with ID: " + strconv.FormatInt(subscription.ID, 10))
	return subscription, nil
}

func (c *StripeController) HandleUSNotification(payload []byte, header string) error {
	event, err := webhook.ConstructEvent(payload, header, viper.GetString("stripe.us.webhook-secret"))
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return c.handleWebhookEvent(event, ente.StripeUS)
}

func (c *StripeController) HandleINNotification(payload []byte, header string) error {
	event, err := webhook.ConstructEvent(payload, header, viper.GetString("stripe.in.webhook-secret"))
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return c.handleWebhookEvent(event, ente.StripeIN)
}

func (c *StripeController) handleWebhookEvent(event stripe.Event, country ente.StripeAccountCountry) error {
	// The event body would already have been logged by the upper layers by the
	// time we get here, so we can only handle the events that we care about. In
	// case we receive an unexpected event, we do log an error though.
	handler := c.findHandlerForEvent(event)
	if handler == nil {
		log.Error("Received an unexpected webhook from stripe:", event.Type)
		return nil
	}
	eventLog, err := handler(event, country)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if eventLog.UserID == 0 {
		// Do not try to log if we do not have an associated user. This can
		// happen, e.g. with out of order webhooks.
		// Or in case of offer application, where events are logged by the Storage Bonus Repo
		//
		// See: Ignore webhooks received before user has been created
		return nil
	}
	err = c.BillingRepo.LogStripePush(eventLog)
	return stacktrace.Propagate(err, "")
}

func (c *StripeController) findHandlerForEvent(event stripe.Event) func(event stripe.Event, country ente.StripeAccountCountry) (ente.StripeEventLog, error) {
	switch event.Type {
	case "checkout.session.completed":
		return c.handleCheckoutSessionCompleted
	case "customer.subscription.updated":
		return c.handleCustomerSubscriptionUpdated
	case "invoice.paid":
		return c.handleInvoicePaid
	case "payment_intent.payment_failed":
		return c.handlePaymentIntentFailed
	default:
		return nil
	}
}

// Payment is successful and the subscription is created.
// You should provision the subscription.
func (c *StripeController) handleCheckoutSessionCompleted(event stripe.Event, country ente.StripeAccountCountry) (ente.StripeEventLog, error) {
	var session stripe.CheckoutSession
	json.Unmarshal(event.Data.Raw, &session)
	if session.ClientReferenceID != "" { // via payments.ente.com, where we inserted the userID
		userID, _ := strconv.ParseInt(session.ClientReferenceID, 10, 64)
		newSubscription, err := c.GetVerifiedSubscription(userID, session.ID)
		if err != nil {
			return ente.StripeEventLog{}, stacktrace.Propagate(err, "")
		}
		stripeSubscription, err := c.getStripeSubscriptionFromSession(userID, session.ID)
		if err != nil {
			return ente.StripeEventLog{}, stacktrace.Propagate(err, "")
		}
		currentSubscription, err := c.BillingRepo.GetUserSubscription(userID)
		if err != nil {
			return ente.StripeEventLog{}, stacktrace.Propagate(err, "")
		}
		if currentSubscription.ExpiryTime >= newSubscription.ExpiryTime &&
			currentSubscription.ProductID != ente.FreePlanProductID {
			if currentSubscription.PaymentProvider != newSubscription.PaymentProvider ||
				currentSubscription.OriginalTransactionID != newSubscription.OriginalTransactionID ||
				currentSubscription.ProductID != newSubscription.ProductID {
				c.notifySkippedPaidStripeSubscriptionReplacement(userID, currentSubscription, newSubscription)
			}
			log.Warn("Webhook is reporting an outdated purchase that was already verified stripeSubscription:", stripeSubscription.ID)
			return ente.StripeEventLog{UserID: userID, StripeSubscription: stripeSubscription, Event: event}, nil
		}
		isUpgradingFromFreePlan := currentSubscription.ProductID == ente.FreePlanProductID
		if isUpgradingFromFreePlan {
			newSubscription.UpgradedAt = timeUtil.Microseconds()
		}
		err = c.BillingRepo.ReplaceSubscription(
			currentSubscription.ID,
			newSubscription,
		)
		if isUpgradingFromFreePlan {
			go func() {
				cur := currency.MustParseISO(string(session.Currency))
				amount := fmt.Sprintf("%v%v", currency.Symbol(cur), float64(session.AmountTotal)/float64(100))
				c.DiscordController.NotifyNewSub(userID, "stripe", amount)
			}()
			go func() {
				c.EmailNotificationCtrl.OnAccountUpgrade(userID)
			}()
		}
		if err != nil {
			return ente.StripeEventLog{}, stacktrace.Propagate(err, "")
		}
		return ente.StripeEventLog{UserID: userID, StripeSubscription: stripeSubscription, Event: event}, nil
	} else {
		priceID, err := c.getPriceIDFromSession(session.ID)
		if err != nil {
			return ente.StripeEventLog{}, stacktrace.Propagate(err, "")
		}
		email := session.CustomerDetails.Email
		err = c.OfferController.ApplyOffer(email, priceID)
		if err != nil {
			return ente.StripeEventLog{}, stacktrace.Propagate(err, "")
		}
	}
	return ente.StripeEventLog{}, nil
}

// Stripe fires this when a subscription starts or changes. For example,
// renewing a subscription, adding a coupon, applying a discount, adding an
// invoice item, and changing plans all trigger this event. In our case, we use
// this only to track plan changes and renewal failures resulting in
// subscriptions going past due.
func (c *StripeController) handleCustomerSubscriptionUpdated(event stripe.Event, country ente.StripeAccountCountry) (ente.StripeEventLog, error) {
	var stripeSubscription stripe.Subscription
	json.Unmarshal(event.Data.Raw, &stripeSubscription)
	currentSubscription, err := c.BillingRepo.GetSubscriptionForTransaction(stripeSubscription.ID, ente.Stripe)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			// See: Ignore webhooks received before user has been created
			log.Warn("Webhook is reporting an event for un-verified subscription stripeSubscriptionID:", stripeSubscription.ID)
			return ente.StripeEventLog{}, nil
		}
		return ente.StripeEventLog{}, stacktrace.Propagate(err, "")
	}
	userID := currentSubscription.UserID
	newSubscription, err := c.getEnteSubscriptionFromStripeSubscription(userID, stripeSubscription)
	if err != nil {
		return ente.StripeEventLog{}, stacktrace.Propagate(err, "")
	}
	// If the customer has changed the plan, we update state in the database. If
	// the plan has not changed, we will ignore this webhook and rely on other
	// events to update the state
	if currentSubscription.ProductID != newSubscription.ProductID {
		c.BillingRepo.ReplaceSubscription(currentSubscription.ID, newSubscription)
	}

	fullStripeSub, err := c.getStripeSubscriptionWithPaymentMethod(currentSubscription)
	if err != nil {
		return ente.StripeEventLog{}, stacktrace.Propagate(err, "")
	}
	defaultPaymentMethodType := getSubscriptionPaymentMethodType(fullStripeSub)

	if stripeSubscription.Status == stripe.SubscriptionStatusPastDue &&
		!usesAllowIncompleteSubscriptionUpdate(defaultPaymentMethodType) {
		// Subscription updates that do not use allow_incomplete surface failures
		// via customer.subscription.updated. SEPA and UPI are handled within
		// handlePaymentIntentFailed to avoid duplicate on-hold emails.
		err = c.sendAccountOnHoldEmail(userID)
		if err != nil {
			return ente.StripeEventLog{}, stacktrace.Propagate(err, "")
		}
	}

	return ente.StripeEventLog{UserID: userID, StripeSubscription: stripeSubscription, Event: event}, nil
}

// Continue to provision the subscription as payments continue to be made.
func (c *StripeController) handleInvoicePaid(event stripe.Event, country ente.StripeAccountCountry) (ente.StripeEventLog, error) {
	var invoice stripe.Invoice
	json.Unmarshal(event.Data.Raw, &invoice)
	stripeSubscriptionID := invoice.Subscription.ID
	currentSubscription, err := c.BillingRepo.GetSubscriptionForTransaction(stripeSubscriptionID, ente.Stripe)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			// See: Ignore webhooks received before user has been created
			if invoice.BillingReason != stripe.InvoiceBillingReasonSubscriptionCreate {
				c.notifyIgnoredPaidStripeWebhook(event.Type, country, stripeSubscriptionID, invoice.Customer.ID)
			}
			log.Warn("Webhook is reporting an event for un-verified subscription stripeSubscriptionID:", stripeSubscriptionID)
			return ente.StripeEventLog{}, nil
		}
		return ente.StripeEventLog{}, stacktrace.Propagate(err, "")
	}

	userID := currentSubscription.UserID
	client := c.StripeClients[currentSubscription.Attributes.StripeAccountCountry]

	stripeSubscription, err := client.Subscriptions.Get(stripeSubscriptionID, nil)
	if err != nil {
		return ente.StripeEventLog{}, stacktrace.Propagate(err, "")
	}

	newExpiryTime := stripeSubscription.CurrentPeriodEnd * 1000 * 1000
	if currentSubscription.ExpiryTime == newExpiryTime {
		//outdated invoice
		log.Warn("Webhook is reporting an outdated purchase that was already verified stripeSubscriptionID:", stripeSubscription.ID)
		return ente.StripeEventLog{UserID: userID, StripeSubscription: *stripeSubscription, Event: event}, nil
	}
	err = c.BillingRepo.UpdateSubscriptionExpiryTime(
		currentSubscription.ID, newExpiryTime)
	if err != nil {
		return ente.StripeEventLog{}, stacktrace.Propagate(err, "")
	}
	return ente.StripeEventLog{UserID: userID, StripeSubscription: *stripeSubscription, Event: event}, nil
}

// Event used to handle failures for payment methods whose subscription updates
// use allow_incomplete (currently SEPA and UPI). Other subscription update
// modes are handled synchronously in UpdateSubscription and
// customer.subscription.updated.
func (c *StripeController) handlePaymentIntentFailed(event stripe.Event, country ente.StripeAccountCountry) (ente.StripeEventLog, error) {
	var paymentIntent stripe.PaymentIntent
	json.Unmarshal(event.Data.Raw, &paymentIntent)
	paymentMethodType := getPaymentIntentErrorPaymentMethodType(paymentIntent)
	if !usesAllowIncompleteSubscriptionUpdate(paymentMethodType) {
		// Ignore events for payment methods that are already handled
		// synchronously.
		log.Info("Ignoring payment intent failed event for payment method handled synchronously")
		return ente.StripeEventLog{}, nil
	}

	client := c.StripeClients[country]
	invoiceID := paymentIntent.Invoice.ID
	invoice, err := client.Invoices.Get(invoiceID, nil)
	if err != nil {
		return ente.StripeEventLog{}, stacktrace.Propagate(err, "")
	}
	stripeSubscriptionID := invoice.Subscription.ID

	currentSubscription, err := c.BillingRepo.GetSubscriptionForTransaction(stripeSubscriptionID, ente.Stripe)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			// See: Ignore webhooks received before user has been created
			log.Warn("Webhook is reporting an event for un-verified subscription stripeSubscriptionID:", stripeSubscriptionID)
		}
		return ente.StripeEventLog{}, stacktrace.Propagate(err, "")
	}
	userID := currentSubscription.UserID

	stripeSubscription, err := client.Subscriptions.Get(stripeSubscriptionID, nil)
	if err != nil {
		return ente.StripeEventLog{}, stacktrace.Propagate(err, "")
	}

	if isPaidStripeInvoice(invoice) {
		log.Info("Ignoring stale payment intent failed event for paid invoice:", invoiceID)
		return ente.StripeEventLog{UserID: userID, StripeSubscription: *stripeSubscription, Event: event}, nil
	}

	productID := stripeSubscription.Items.Data[0].Price.ID
	// If the current subscription is not the same as the one in the webhook,
	// then ignore
	if currentSubscription.ProductID != productID {
		// no-op
		log.Warn("Webhook is reporting un-verified subscription update", stripeSubscription.ID, "invoiceID:", invoiceID)
		return ente.StripeEventLog{UserID: userID, StripeSubscription: *stripeSubscription, Event: event}, nil
	}
	// If the current subscription is the same as the one in the webhook, then
	// we need to expire the subscription, and send an email to the user.
	newExpiryTime := time.Now().UnixMicro()
	err = c.BillingRepo.UpdateSubscriptionExpiryTime(
		currentSubscription.ID, newExpiryTime)
	if err != nil {
		return ente.StripeEventLog{}, stacktrace.Propagate(err, "")
	}

	err = c.BillingRepo.UpdateSubscriptionCancellationStatus(userID, true)
	if err != nil {
		return ente.StripeEventLog{}, stacktrace.Propagate(err, "")
	}

	err = c.sendAccountOnHoldEmail(userID)
	if err != nil {
		return ente.StripeEventLog{}, stacktrace.Propagate(err, "")
	}

	return ente.StripeEventLog{UserID: userID, StripeSubscription: *stripeSubscription, Event: event}, nil
}

func (c *StripeController) UpdateSubscription(stripeID string, userID int64) (ente.SubscriptionUpdateResponse, error) {
	subscription, err := c.BillingRepo.GetUserSubscription(userID)
	if err != nil {
		return ente.SubscriptionUpdateResponse{}, stacktrace.Propagate(err, "")
	}
	newPlan, newStripeAccountCountry, err := c.getPlanAndAccount(stripeID)
	if err != nil {
		return ente.SubscriptionUpdateResponse{}, stacktrace.Propagate(err, "")
	}
	if subscription.PaymentProvider != ente.Stripe || subscription.ProductID == stripeID || subscription.Attributes.StripeAccountCountry != newStripeAccountCountry {
		return ente.SubscriptionUpdateResponse{}, stacktrace.Propagate(ente.ErrBadRequest, "")
	}
	if newPlan.Storage < subscription.Storage { // Downgrade
		canDowngrade, canDowngradeErr := c.CommonBillCtrl.CanDowngradeToGivenStorage(newPlan.Storage, userID)
		if canDowngradeErr != nil {
			return ente.SubscriptionUpdateResponse{}, stacktrace.Propagate(canDowngradeErr, "")
		}
		if !canDowngrade {
			return ente.SubscriptionUpdateResponse{}, stacktrace.Propagate(ente.ErrCannotDowngrade, "")
		}
		log.Info("Usage is good")

	}
	stripeSubscription, err := c.getStripeSubscriptionWithPaymentMethod(subscription)
	if err != nil {
		return ente.SubscriptionUpdateResponse{}, stacktrace.Propagate(err, "")
	}
	defaultPaymentMethodType := getSubscriptionPaymentMethodType(stripeSubscription)
	var paymentBehavior stripe.SubscriptionPaymentBehavior
	if usesAllowIncompleteSubscriptionUpdate(defaultPaymentMethodType) {
		paymentBehavior = stripe.SubscriptionPaymentBehaviorAllowIncomplete
	} else {
		paymentBehavior = stripe.SubscriptionPaymentBehaviorPendingIfIncomplete
	}
	params := stripe.SubscriptionParams{
		ProrationBehavior: stripe.String(string(stripe.SubscriptionProrationBehaviorAlwaysInvoice)),
		Items: []*stripe.SubscriptionItemsParams{
			{
				ID:    stripe.String(stripeSubscription.Items.Data[0].ID),
				Price: stripe.String(stripeID),
			},
		},
		PaymentBehavior: stripe.String(string(paymentBehavior)),
	}
	params.AddExpand("latest_invoice.payment_intent")
	client := c.StripeClients[subscription.Attributes.StripeAccountCountry]
	newStripeSubscription, err := client.Subscriptions.Update(subscription.OriginalTransactionID, &params)
	if err != nil {
		stripeError := err.(*stripe.Error)
		switch stripeError.Type {
		case stripe.ErrorTypeCard:
			return ente.SubscriptionUpdateResponse{Status: "requires_payment_method"}, nil
		default:
			return ente.SubscriptionUpdateResponse{}, stacktrace.Propagate(err, "")
		}
	}
	if paymentBehavior == stripe.SubscriptionPaymentBehaviorPendingIfIncomplete {
		if newStripeSubscription.PendingUpdate != nil {
			switch newStripeSubscription.LatestInvoice.PaymentIntent.Status {
			case stripe.PaymentIntentStatusRequiresAction:
				return ente.SubscriptionUpdateResponse{Status: "requires_action", ClientSecret: newStripeSubscription.LatestInvoice.PaymentIntent.ClientSecret}, nil
			case stripe.PaymentIntentStatusRequiresPaymentMethod:
				inv := newStripeSubscription.LatestInvoice
				client.Invoices.VoidInvoice(inv.ID, nil)
				return ente.SubscriptionUpdateResponse{Status: "requires_payment_method"}, nil
			}
			return ente.SubscriptionUpdateResponse{}, stacktrace.Propagate(ente.ErrBadRequest, "")
		}
	} else if newStripeSubscription.LatestInvoice != nil && newStripeSubscription.LatestInvoice.PaymentIntent != nil {
		switch newStripeSubscription.LatestInvoice.PaymentIntent.Status {
		case stripe.PaymentIntentStatusRequiresAction:
			return ente.SubscriptionUpdateResponse{Status: "requires_action", ClientSecret: newStripeSubscription.LatestInvoice.PaymentIntent.ClientSecret}, nil
		case stripe.PaymentIntentStatusRequiresPaymentMethod:
			return ente.SubscriptionUpdateResponse{Status: "requires_payment_method"}, nil
		case stripe.PaymentIntentStatusProcessing:
			return ente.SubscriptionUpdateResponse{Status: "success"}, nil
		case stripe.PaymentIntentStatusSucceeded:
			return ente.SubscriptionUpdateResponse{Status: "success"}, nil
		default:
			return ente.SubscriptionUpdateResponse{}, stacktrace.Propagate(ente.ErrBadRequest, "")
		}
	}
	return ente.SubscriptionUpdateResponse{Status: "success"}, nil
}

func (c *StripeController) UpdateSubscriptionCancellationStatus(userID int64, shouldCancel bool) (ente.Subscription, error) {
	subscription, err := c.BillingRepo.GetUserSubscription(userID)
	if err != nil {
		// error sql.ErrNoRows not possible as user must at least have a free subscription
		return ente.Subscription{}, stacktrace.Propagate(err, "")
	}
	if subscription.PaymentProvider != ente.Stripe {
		return ente.Subscription{}, stacktrace.Propagate(ente.ErrBadRequest, "")
	}

	if subscription.Attributes.IsCancelled == shouldCancel {
		// no-op
		return subscription, nil
	}

	client := c.StripeClients[subscription.Attributes.StripeAccountCountry]
	params := &stripe.SubscriptionParams{
		CancelAtPeriodEnd: stripe.Bool(shouldCancel),
	}
	_, err = client.Subscriptions.Update(subscription.OriginalTransactionID, params)
	if err != nil {
		return ente.Subscription{}, c.handleStripeError(err, userID, "UpdateSubscriptionCancellationStatus")
	}
	if shouldCancel {
		err = c.CommonBillCtrl.OnSubscriptionCancelled(userID)
	} else {
		err = c.BillingRepo.UpdateSubscriptionCancellationStatus(userID, false)
	}
	if err != nil {
		return ente.Subscription{}, stacktrace.Propagate(err, "")
	}
	subscription.Attributes.IsCancelled = shouldCancel
	return subscription, nil
}

func (c *StripeController) GetStripeCustomerPortal(userID int64, redirectRootURL string) (string, error) {
	subscription, err := c.BillingRepo.GetUserSubscription(userID)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if subscription.PaymentProvider != ente.Stripe {
		return "", stacktrace.Propagate(ente.ErrBadRequest, "")
	}
	client := c.StripeClients[subscription.Attributes.StripeAccountCountry]

	params := &stripe.BillingPortalSessionParams{
		Customer:  stripe.String(subscription.Attributes.CustomerID),
		ReturnURL: stripe.String(redirectRootURL),
	}
	ps, err := client.BillingPortalSessions.New(params)
	if err != nil {
		return "", c.handleStripeError(err, userID, "GetStripeCustomerPortal")
	}
	return ps.URL, nil
}

func (c *StripeController) getStripeSubscriptionWithPaymentMethod(subscription ente.Subscription) (stripe.Subscription, error) {
	client := c.StripeClients[subscription.Attributes.StripeAccountCountry]
	params := &stripe.SubscriptionParams{}
	params.AddExpand("default_payment_method")
	params.AddExpand("default_source")
	params.AddExpand("customer.invoice_settings.default_payment_method")
	params.AddExpand("customer.default_source")
	stripeSubscription, err := client.Subscriptions.Get(subscription.OriginalTransactionID, params)
	if err != nil {
		return stripe.Subscription{}, stacktrace.Propagate(err, "")
	}
	return *stripeSubscription, nil
}

func (c *StripeController) sendAccountOnHoldEmail(userID int64) error {
	user, err := c.UserRepo.Get(userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	err = email.SendTemplatedEmail([]string{user.Email}, "ente", "support@ente.com",
		ente.AccountOnHoldEmailSubject, ente.OnHoldTemplate, map[string]interface{}{
			"PaymentProvider": "Stripe",
		}, nil)
	return err
}

func (c *StripeController) notifyIgnoredPaidStripeWebhook(eventType string, country ente.StripeAccountCountry, stripeSubscriptionID string, customerID string) {
	message := fmt.Sprintf(
		"Paid Stripe webhook `%s` for unknown subscription `%s` on `%s` account (customer `%s`) was acknowledged with 2xx and no subscription row was updated.",
		eventType,
		stripeSubscriptionID,
		country,
		customerID,
	)
	c.DiscordController.NotifyThrottled(message, 30*time.Minute)
}

func (c *StripeController) notifySkippedPaidStripeSubscriptionReplacement(userID int64, currentSubscription ente.Subscription, newSubscription ente.Subscription) {
	message := fmt.Sprintf(
		"Paid Stripe checkout for user `%d` was acknowledged with 2xx but subscription replacement was skipped. Current: provider=`%s` txn=`%s` product=`%s` expiry=`%d`; incoming: provider=`%s` txn=`%s` product=`%s` expiry=`%d`.",
		userID,
		currentSubscription.PaymentProvider,
		currentSubscription.OriginalTransactionID,
		currentSubscription.ProductID,
		currentSubscription.ExpiryTime,
		newSubscription.PaymentProvider,
		newSubscription.OriginalTransactionID,
		newSubscription.ProductID,
		newSubscription.ExpiryTime,
	)
	c.DiscordController.NotifyThrottled(message, 30*time.Minute)
}

func (c *StripeController) getStripeSubscriptionFromSession(userID int64, checkoutSessionID string) (stripe.Subscription, error) {
	subscription, err := c.BillingRepo.GetUserSubscription(userID)
	if err != nil {
		return stripe.Subscription{}, stacktrace.Propagate(err, "")
	}
	var stripeClient *client.API
	if subscription.PaymentProvider == ente.Stripe {
		stripeClient = c.StripeClients[subscription.Attributes.StripeAccountCountry]
	} else {
		stripeClient = c.StripeClients[ente.DefaultStripeAccountCountry]
	}
	params := &stripe.CheckoutSessionParams{}
	params.AddExpand("subscription")
	checkoutSession, err := stripeClient.CheckoutSessions.Get(checkoutSessionID, params)
	if err != nil {
		return stripe.Subscription{}, stacktrace.Propagate(err, "")
	}
	if (*checkoutSession.Subscription).Status != stripe.SubscriptionStatusActive {
		return stripe.Subscription{}, stacktrace.Propagate(&stripe.InvalidRequestError{}, "")
	}
	return *checkoutSession.Subscription, nil
}

func (c *StripeController) getPriceIDFromSession(sessionID string) (string, error) {
	stripeClient := c.StripeClients[ente.DefaultStripeAccountCountry]
	params := &stripe.CheckoutSessionListLineItemsParams{}
	params.AddExpand("data.price")
	items := stripeClient.CheckoutSessions.ListLineItems(sessionID, params)
	for items.Next() { // Return the first PriceID that has been fetched
		return items.LineItem().Price.ID, nil
	}
	return "", stacktrace.Propagate(ente.ErrNotFound, "")
}

func (c *StripeController) getUserStripeSubscription(userID int64) (stripe.Subscription, error) {
	subscription, err := c.BillingRepo.GetUserSubscription(userID)
	if err != nil {
		return stripe.Subscription{}, stacktrace.Propagate(err, "")
	}
	if subscription.PaymentProvider != ente.Stripe {
		return stripe.Subscription{}, stacktrace.Propagate(ente.ErrCannotSwitchPaymentProvider, "")
	}
	client := c.StripeClients[subscription.Attributes.StripeAccountCountry]
	stripeSubscription, err := client.Subscriptions.Get(subscription.OriginalTransactionID, nil)
	if err != nil {
		return stripe.Subscription{}, stacktrace.Propagate(err, "")
	}
	return *stripeSubscription, nil
}

func (c *StripeController) getPlanAndAccount(stripeID string) (ente.BillingPlan, ente.StripeAccountCountry, error) {
	for stripeAccountCountry, billingPlansCountryWise := range c.BillingPlansPerAccount {
		for _, plans := range billingPlansCountryWise {
			for _, plan := range plans {
				if plan.StripeID == stripeID {
					return plan, stripeAccountCountry, nil
				}
			}
		}
	}
	return ente.BillingPlan{}, "", stacktrace.Propagate(ente.ErrNotFound, "")
}

func (c *StripeController) getEnteSubscriptionFromStripeSubscription(userID int64, stripeSubscription stripe.Subscription) (ente.Subscription, error) {
	productID := stripeSubscription.Items.Data[0].Price.ID
	plan, stripeAccountCountry, err := c.getPlanAndAccount(productID)
	if err != nil {
		return ente.Subscription{}, stacktrace.Propagate(err, "")
	}
	s := ente.Subscription{
		UserID:                userID,
		PaymentProvider:       ente.Stripe,
		ProductID:             productID,
		Storage:               plan.Storage,
		Attributes:            ente.SubscriptionAttributes{CustomerID: stripeSubscription.Customer.ID, IsCancelled: false, StripeAccountCountry: stripeAccountCountry},
		OriginalTransactionID: stripeSubscription.ID,
		ExpiryTime:            stripeSubscription.CurrentPeriodEnd * 1000 * 1000,
	}
	return s, nil
}

func (c *StripeController) UpdateBillingEmail(subscription ente.Subscription, newEmail string) error {
	params := &stripe.CustomerParams{Email: &newEmail}
	client := c.StripeClients[subscription.Attributes.StripeAccountCountry]
	_, err := client.Customers.Update(
		subscription.Attributes.CustomerID,
		params,
	)
	if err != nil {
		return stacktrace.Propagate(err, "failed to update stripe customer emailID")
	}
	return nil
}

func (c *StripeController) CancelSubAndDeleteCustomer(subscription ente.Subscription, logger *log.Entry) error {
	client := c.StripeClients[subscription.Attributes.StripeAccountCountry]
	if !subscription.Attributes.IsCancelled {
		prorateRefund := true
		logger.Info("cancelling sub with prorated refund")
		_, err := client.Subscriptions.Update(subscription.OriginalTransactionID, nil)
		if err != nil {
			stripeError := err.(*stripe.Error)
			errorMsg := fmt.Sprintf("subscription updation failed during account deletion: %s, %s", stripeError.Msg, stripeError.Code)
			log.Error(errorMsg)
			c.DiscordController.Notify(errorMsg)
			if stripeError.HTTPStatusCode == http.StatusNotFound {
				log.Error("Ignoring error since an active subscription could not be found")
				return nil
			} else if stripeError.HTTPStatusCode == http.StatusBadRequest {
				log.Error("Bad request while trying to delete account")
				return nil
			}
			return stacktrace.Propagate(err, "")
		}
		_, err = client.Subscriptions.Cancel(subscription.OriginalTransactionID, &stripe.SubscriptionCancelParams{
			Prorate: &prorateRefund,
		})
		if err != nil {
			stripeError := err.(*stripe.Error)
			logger.Error(fmt.Sprintf("subscription cancel failed msg= %s for userID=%d"+stripeError.Msg, subscription.UserID))
			// ignore if subscription doesn't exist, already deleted
			if stripeError.HTTPStatusCode != 404 {
				return stacktrace.Propagate(err, "")
			}
		}
		err = c.CommonBillCtrl.OnSubscriptionCancelled(subscription.UserID)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
	}
	logger.Info("deleting customer from stripe")
	_, err := client.Customers.Del(
		subscription.Attributes.CustomerID,
		&stripe.CustomerParams{},
	)
	if err != nil {
		stripeError := err.(*stripe.Error)
		switch stripeError.Type {
		case stripe.ErrorTypeInvalidRequest:
			if stripe.ErrorCodeResourceMissing == stripeError.Code {
				return nil
			}
			return stacktrace.Propagate(err, "failed to delete customer %s", subscription.Attributes.CustomerID)
		default:
			return stacktrace.Propagate(err, "failed to delete customer %s", subscription.Attributes.CustomerID)
		}
	}
	return nil
}

func getSubscriptionPaymentMethodType(stripeSubscription stripe.Subscription) stripe.PaymentMethodType {
	if stripeSubscription.DefaultPaymentMethod == nil {
		if stripeSubscription.DefaultSource != nil &&
			stripeSubscription.DefaultSource.Type == stripe.PaymentSourceTypeCard {
			return stripe.PaymentMethodTypeCard
		}
		if stripeSubscription.Customer != nil {
			if stripeSubscription.Customer.InvoiceSettings != nil &&
				stripeSubscription.Customer.InvoiceSettings.DefaultPaymentMethod != nil {
				return stripeSubscription.Customer.InvoiceSettings.DefaultPaymentMethod.Type
			}
			if stripeSubscription.Customer.DefaultSource != nil &&
				stripeSubscription.Customer.DefaultSource.Type == stripe.PaymentSourceTypeCard {
				return stripe.PaymentMethodTypeCard
			}
		}
		log.Info("No default payment method found on subscription or customer")
		return ""
	}
	return stripeSubscription.DefaultPaymentMethod.Type
}

func usesAllowIncompleteSubscriptionUpdate(paymentMethodType stripe.PaymentMethodType) bool {
	return paymentMethodType == stripe.PaymentMethodTypeSepaDebit || paymentMethodType == stripe.PaymentMethodType("upi")
}

func isPaidStripeInvoice(invoice *stripe.Invoice) bool {
	return invoice.Paid || invoice.Status == stripe.InvoiceStatusPaid
}

func getPaymentIntentErrorPaymentMethodType(paymentIntent stripe.PaymentIntent) stripe.PaymentMethodType {
	if paymentIntent.LastPaymentError == nil {
		return ""
	}
	if paymentIntent.LastPaymentError.PaymentMethod != nil {
		return paymentIntent.LastPaymentError.PaymentMethod.Type
	}
	if paymentIntent.LastPaymentError.Source != nil &&
		paymentIntent.LastPaymentError.Source.Type == stripe.PaymentSourceTypeCard {
		return stripe.PaymentMethodTypeCard
	}
	return paymentIntent.LastPaymentError.PaymentMethodType
}

// handleStripeError processes Stripe errors, sends Discord alerts for invalid_request_error,
// and returns user-friendly errors to prevent 5xx responses
func (c *StripeController) handleStripeError(err error, userID int64, context string) error {
	if err == nil {
		return nil
	}

	stripeError, ok := err.(*stripe.Error)
	if !ok {
		// Not a Stripe error, propagate as-is
		return stacktrace.Propagate(err, "")
	}

	// Check if it's an invalid_request_error
	if stripeError.Type == stripe.ErrorTypeInvalidRequest {
		// Send Discord alert with details
		alertMsg := fmt.Sprintf(
			"⚠️ Stripe Invalid Request Error\n"+
				"**Context:** %s\n"+
				"**User ID:** %d\n"+
				"**Error Code:** %s\n"+
				"**Message:** %s\n"+
				"**Status:** %d\n"+
				"**Request ID:** %s",
			context,
			userID,
			stripeError.Code,
			stripeError.Msg,
			stripeError.HTTPStatusCode,
			stripeError.RequestID,
		)
		c.DiscordController.Notify(alertMsg)

		// Return user-friendly error based on error code
		var userMsg string
		switch stripeError.Code {
		case stripe.ErrorCodeResourceMissing:
			userMsg = "The requested resource no longer exists. Please create a new subscription or contact support."
		default:
			// For other invalid_request_error codes, use the Stripe message if available
			if stripeError.Msg != "" {
				userMsg = fmt.Sprintf("Unable to process request: %s", stripeError.Msg)
			} else {
				userMsg = "Unable to process your request. Please contact support if the issue persists."
			}
		}

		return stacktrace.Propagate(ente.NewBadRequestWithMessage(userMsg), "")
	}

	// For other Stripe errors, propagate as-is
	return stacktrace.Propagate(err, "")
}
