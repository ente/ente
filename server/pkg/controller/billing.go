package controller

import (
	"context"
	"database/sql"
	"errors"
	"slices"
	"strconv"

	"github.com/ente/museum/pkg/controller/commonbilling"

	"github.com/ente/museum/pkg/repo/storagebonus"

	"github.com/ente/museum/pkg/controller/discord"
	"github.com/ente/museum/pkg/controller/email"
	"github.com/ente/museum/pkg/utils/billing"
	"github.com/ente/museum/pkg/utils/network"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/viper"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/repo"
)

// BillingController provides abstractions for handling billing related queries
type BillingController struct {
	BillingPlansPerAccount ente.BillingPlansPerAccount
	BillingRepo            *repo.BillingRepository
	UserRepo               *repo.UserRepository
	UsageRepo              *repo.UsageRepository
	StorageBonusRepo       *storagebonus.Repository
	AppStoreController     *AppStoreController
	PlayStoreController    *PlayStoreController
	StripeController       *StripeController
	DiscordController      *discord.DiscordController
	EmailNotificationCtrl  *email.EmailNotificationController
	CommonBillCtrl         *commonbilling.Controller
}

// Return a new instance of BillingController
func NewBillingController(
	plans ente.BillingPlansPerAccount,
	appStoreController *AppStoreController,
	playStoreController *PlayStoreController,
	stripeController *StripeController,
	discordController *discord.DiscordController,
	emailNotificationCtrl *email.EmailNotificationController,
	billingRepo *repo.BillingRepository,
	userRepo *repo.UserRepository,
	usageRepo *repo.UsageRepository,
	storageBonusRepo *storagebonus.Repository,
	commonBillCtrl *commonbilling.Controller,
) *BillingController {
	return &BillingController{
		BillingPlansPerAccount: plans,
		BillingRepo:            billingRepo,
		UserRepo:               userRepo,
		UsageRepo:              usageRepo,
		AppStoreController:     appStoreController,
		PlayStoreController:    playStoreController,
		StripeController:       stripeController,
		DiscordController:      discordController,
		EmailNotificationCtrl:  emailNotificationCtrl,
		StorageBonusRepo:       storageBonusRepo,
		CommonBillCtrl:         commonBillCtrl,
	}
}

// GetPlansV2 returns the available subscription plans for the given country and stripe account
func (c *BillingController) GetPlansV2(countryCode string, stripeAccountCountry ente.StripeAccountCountry) []ente.BillingPlan {
	plans := c.getAllPlans(countryCode, stripeAccountCountry)
	result := make([]ente.BillingPlan, 0)
	ids := billing.GetActivePlanIDs()
	for _, plan := range plans {
		if slices.Contains(ids, plan.ID) {
			result = append(result, plan)
		}
	}
	return result
}

// GetStripeAccountCountry returns the stripe account country the user's existing plan is from
// if he doesn't have a stripe subscription then ente.DefaultStripeAccountCountry is returned
func (c *BillingController) GetStripeAccountCountry(userID int64) (ente.StripeAccountCountry, error) {
	subscription, err := c.BillingRepo.GetUserSubscription(userID)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if subscription.PaymentProvider != ente.Stripe {
		//if user doesn't have a stripe subscription, return the default stripe account country
		return ente.DefaultStripeAccountCountry, nil
	} else {
		return subscription.Attributes.StripeAccountCountry, nil
	}
}

// GetUserPlans returns the active plans for a user
func (c *BillingController) GetUserPlans(ctx *gin.Context, userID int64) ([]ente.BillingPlan, error) {
	stripeAccountCountry, err := c.GetStripeAccountCountry(userID)
	if err != nil {
		return []ente.BillingPlan{}, stacktrace.Propagate(err, "Failed to get user's country stripe account")
	}
	// always return the plans based on the user's country determined by the IP
	return c.GetPlansV2(network.GetClientCountry(ctx), stripeAccountCountry), nil

}

// GetSubscription returns the current subscription for a user if any
func (c *BillingController) GetSubscription(ctx *gin.Context, userID int64) (ente.Subscription, error) {
	s, err := c.BillingRepo.GetUserSubscription(userID)
	if err != nil {
		return ente.Subscription{}, stacktrace.Propagate(err, "")
	}
	plan, err := c.getPlanForCountry(s, network.GetClientCountry(ctx))
	if err != nil {
		return ente.Subscription{}, stacktrace.Propagate(err, "")
	}
	s.Price = plan.Price
	s.Period = plan.Period
	return s, nil
}

func (c *BillingController) GetRedirectURL(ctx *gin.Context) (string, error) {
	whitelistedRedirectURLs := viper.GetStringSlice("stripe.whitelisted-redirect-urls")
	redirectURL := ctx.Query("redirectURL")
	if len(redirectURL) > 0 && redirectURL[len(redirectURL)-1:] == "/" { // Ignore the trailing slash
		redirectURL = redirectURL[:len(redirectURL)-1]
	}
	for _, ar := range whitelistedRedirectURLs {
		if ar == redirectURL {
			return ar, nil
		}
	}
	return "", stacktrace.Propagate(ente.ErrBadRequest, "not a whitelistedRedirectURL- %s", redirectURL)
}

// GetActiveSubscription returns user's active subscription or throws a error if no active subscription
func (c *BillingController) GetActiveSubscription(userID int64) (ente.Subscription, error) {
	subscription, err := c.BillingRepo.GetUserSubscription(userID)
	if errors.Is(err, sql.ErrNoRows) {
		return subscription, ente.ErrNoActiveSubscription
	}
	if err != nil {
		return subscription, stacktrace.Propagate(err, "")
	}
	expiryBuffer := int64(0)
	if value, ok := billing.ProviderToExpiryGracePeriodMap[subscription.PaymentProvider]; ok {
		expiryBuffer = value
	}
	if (subscription.ExpiryTime + expiryBuffer) < time.Microseconds() {
		return subscription, ente.ErrNoActiveSubscription
	}
	return subscription, nil
}

// HasActiveSelfOrFamilySubscription validates if the user or user's family admin has active subscription
func (c *BillingController) HasActiveSelfOrFamilySubscription(userID int64, mustBeOnPaidPlan bool) error {
	var subscriptionUserID int64
	familyAdminID, err := c.UserRepo.GetFamilyAdminID(userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if familyAdminID != nil {
		subscriptionUserID = *familyAdminID
	} else {
		subscriptionUserID = userID
	}
	_, err = c.GetActiveSubscription(subscriptionUserID)
	if err != nil {
		if errors.Is(err, ente.ErrNoActiveSubscription) {
			storage, storeErr := c.StorageBonusRepo.GetPaidAddonSurplusStorage(context.Background(), subscriptionUserID)
			if storeErr != nil {
				return storeErr
			}
			if *storage > 0 {
				return nil
			}
		}
		return stacktrace.Propagate(err, "")
	}
	if mustBeOnPaidPlan {
		isPayingUser, err := c.BillingRepo.IsUserOnPaidPlan(subscriptionUserID)
		if err != nil {
			return stacktrace.Propagate(err, "failed to check if user is on paid plan")
		}
		if !isPayingUser {
			return ente.ErrSharingDisabledForFreeAccounts
		}
	}
	return nil
}

// VerifySubscription verifies and returns the verified subscription
func (c *BillingController) VerifySubscription(
	userID int64,
	paymentProvider ente.PaymentProvider,
	productID string,
	verificationData string) (ente.Subscription, error) {
	if productID == ente.FreePlanProductID {
		return c.BillingRepo.GetUserSubscription(userID)
	}
	var newSubscription ente.Subscription
	var err error
	switch paymentProvider {
	case ente.PlayStore:
		newSubscription, err = c.PlayStoreController.GetVerifiedSubscription(userID, productID, verificationData)
	case ente.AppStore:
		newSubscription, err = c.AppStoreController.GetVerifiedSubscription(userID, productID, verificationData)
	case ente.Stripe:
		newSubscription, err = c.StripeController.GetVerifiedSubscription(userID, verificationData)
	default:
		err = stacktrace.Propagate(ente.ErrBadRequest, "")
	}
	if err != nil {
		return ente.Subscription{}, stacktrace.Propagate(err, "")
	}
	currentSubscription, err := c.BillingRepo.GetUserSubscription(userID)
	if err != nil {
		return ente.Subscription{}, stacktrace.Propagate(err, "")
	}
	newSubscriptionExpiresSooner := newSubscription.ExpiryTime < currentSubscription.ExpiryTime
	isUpgradingFromFreePlan := currentSubscription.ProductID == ente.FreePlanProductID
	hasChangedProductID := currentSubscription.ProductID != newSubscription.ProductID
	isOutdatedPurchase := !isUpgradingFromFreePlan && !hasChangedProductID && newSubscriptionExpiresSooner
	if isOutdatedPurchase {
		// User is reporting an outdated purchase that was already verified
		// no-op
		log.Info("Outdated purchase reported")
		return currentSubscription, nil
	}
	if newSubscription.Storage < currentSubscription.Storage {
		canDowngrade, canDowngradeErr := c.CommonBillCtrl.CanDowngradeToGivenStorage(newSubscription.Storage, userID)
		if canDowngradeErr != nil {
			return ente.Subscription{}, stacktrace.Propagate(canDowngradeErr, "")
		}
		if !canDowngrade {
			return ente.Subscription{}, stacktrace.Propagate(ente.ErrCannotDowngrade, "")
		}
		log.Info("Usage is good")
	}
	if newSubscription.OriginalTransactionID != "" && newSubscription.OriginalTransactionID != "none" {
		existingSub, existingSubErr := c.BillingRepo.GetSubscriptionForTransaction(newSubscription.OriginalTransactionID, paymentProvider)
		if existingSubErr != nil {
			if errors.Is(existingSubErr, sql.ErrNoRows) {
				log.Info("No subscription created yet")
			} else {
				log.Info("Something went wrong")
				log.WithError(existingSubErr).Error("GetSubscriptionForTransaction failed")
				return ente.Subscription{}, stacktrace.Propagate(existingSubErr, "")
			}
		} else {
			if existingSub.UserID != userID {
				log.WithFields(log.Fields{
					"original_transaction_id": existingSub.OriginalTransactionID,
					"existing_user":           existingSub.UserID,
					"current_user":            userID,
				}).Error("Subscription for given transactionID is attached with different user")
				log.Info("Subscription attached to different user")
				return ente.Subscription{}, stacktrace.Propagate(&ente.ErrSubscriptionAlreadyClaimed, "Subscription with txn id %s already associated with user %d", newSubscription.OriginalTransactionID, existingSub.UserID)
			}
		}
	}
	if isUpgradingFromFreePlan {
		newSubscription.UpgradedAt = time.Microseconds()
	}
	err = c.BillingRepo.ReplaceSubscription(
		currentSubscription.ID,
		newSubscription,
	)
	if err != nil {
		return ente.Subscription{}, stacktrace.Propagate(err, "")
	}
	log.Info("Replaced subscription")
	newSubscription.ID = currentSubscription.ID
	if paymentProvider == ente.PlayStore &&
		newSubscription.OriginalTransactionID != currentSubscription.OriginalTransactionID {
		// Acknowledge to PlayStore in case of upgrades/downgrades/renewals
		err = c.PlayStoreController.AcknowledgeSubscription(newSubscription.ProductID, verificationData)
		if err != nil {
			log.Error("Error acknowledging subscription ", err)
		}
	}
	if isUpgradingFromFreePlan {
		go func() {
			amount := "unknown"
			plan, _, err := c.getPlanWithCountry(newSubscription)
			if err != nil {
				log.Error(err)
			} else {
				amount = plan.Price
			}
			c.DiscordController.NotifyNewSub(userID, string(paymentProvider), amount)
		}()
		go func() {
			c.EmailNotificationCtrl.OnAccountUpgrade(userID)
		}()
	}
	log.Info("Returning new subscription with ID " + strconv.FormatInt(newSubscription.ID, 10))
	return newSubscription, nil
}

func (c *BillingController) getAllPlans(countryCode string, stripeAccountCountry ente.StripeAccountCountry) []ente.BillingPlan {
	if slices.Contains(billing.CountriesInEU, countryCode) {
		countryCode = "EU"
	}
	countryWisePlans := c.BillingPlansPerAccount[stripeAccountCountry]
	if plans, found := countryWisePlans[countryCode]; found {
		return plans
	}
	// unable to find plans for given country code, return plans for default country
	defaultCountry := billing.GetDefaultPlanCountry()
	return countryWisePlans[defaultCountry]
}

func (c *BillingController) UpdateBillingEmail(userID int64, newEmail string) error {
	subscription, err := c.BillingRepo.GetUserSubscription(userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	hasStripeSubscription := subscription.PaymentProvider == ente.Stripe
	if hasStripeSubscription {
		err = c.StripeController.UpdateBillingEmail(subscription, newEmail)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
	}
	return nil
}

func (c *BillingController) UpdateSubscription(r ente.UpdateSubscriptionRequest) error {
	subscription, err := c.BillingRepo.GetUserSubscription(r.UserID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	newSubscription := ente.Subscription{
		Storage:               r.Storage,
		ExpiryTime:            r.ExpiryTime,
		ProductID:             r.ProductID,
		PaymentProvider:       r.PaymentProvider,
		OriginalTransactionID: r.TransactionID,
		Attributes:            r.Attributes,
	}
	err = c.BillingRepo.ReplaceSubscription(subscription.ID, newSubscription)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	err = c.BillingRepo.LogAdminTriggeredSubscriptionUpdate(r)
	return stacktrace.Propagate(err, "")
}

func (c *BillingController) HandleAccountDeletion(ctx context.Context, userID int64, logger *log.Entry) (isCancelled bool, err error) {
	logger.Info("updating billing on account deletion")
	subscription, err := c.BillingRepo.GetUserSubscription(userID)
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	billingLogger := logger.WithFields(log.Fields{
		"customer_id":            subscription.Attributes.CustomerID,
		"is_cancelled":           subscription.Attributes.IsCancelled,
		"original_txn_id":        subscription.OriginalTransactionID,
		"payment_provider":       subscription.PaymentProvider,
		"product_id":             subscription.ProductID,
		"stripe_account_country": subscription.Attributes.StripeAccountCountry,
	})
	billingLogger.Info("subscription fetched")
	// user on free plan, no action required
	if subscription.ProductID == ente.FreePlanProductID {
		billingLogger.Info("user on free plan")
		return true, nil
	}
	if subscription.ProductID == "" {
		return false, stacktrace.NewError("unexpected product id %s", subscription.ProductID)
	}
	isCancelled = subscription.Attributes.IsCancelled
	// delete customer data from Stripe if user is on paid plan.
	if subscription.PaymentProvider == ente.Stripe {
		err = c.StripeController.CancelSubAndDeleteCustomer(subscription, billingLogger)
		if err != nil {
			return false, stacktrace.Propagate(err, "")
		}
		// on customer deletion, subscription is automatically cancelled
		isCancelled = true
	} else if subscription.PaymentProvider == ente.AppStore || subscription.PaymentProvider == ente.PlayStore {
		logger.Info("Updating originalTransactionID for app/playStore provider")
		err := c.BillingRepo.UpdateTransactionIDOnDeletion(userID)
		if err != nil {
			return false, stacktrace.Propagate(err, "")
		}
	}
	return isCancelled, nil
}

func (c *BillingController) getPlanWithCountry(s ente.Subscription) (ente.BillingPlan, string, error) {
	var allPlans ente.BillingPlansPerCountry
	if s.PaymentProvider == ente.Stripe {
		allPlans = c.BillingPlansPerAccount[s.Attributes.StripeAccountCountry]
	} else {
		allPlans = c.BillingPlansPerAccount[ente.DefaultStripeAccountCountry]
	}
	subProductID := s.ProductID
	for country, plans := range allPlans {
		for _, plan := range plans {
			if s.PaymentProvider == ente.Stripe && subProductID == plan.StripeID {
				return plan, country, nil
			} else if s.PaymentProvider == ente.PlayStore && subProductID == plan.AndroidID {
				return plan, country, nil
			} else if s.PaymentProvider == ente.AppStore && subProductID == plan.IOSID {
				return plan, country, nil
			} else if (s.PaymentProvider == ente.BitPay || s.PaymentProvider == ente.Paypal) && subProductID == plan.ID {
				return plan, country, nil
			}
		}
	}
	if s.ProductID == ente.FreePlanProductID || s.ProductID == ente.FamilyPlanProductID {
		return ente.BillingPlan{Period: ente.PeriodYear}, "", nil
	}

	return ente.BillingPlan{}, "", stacktrace.Propagate(ente.ErrNotFound, "unable to get plan for subscription")
}

func (c *BillingController) getPlanForCountry(s ente.Subscription, countryCode string) (ente.BillingPlan, error) {
	var allPlans []ente.BillingPlan
	if s.PaymentProvider == ente.Stripe {
		allPlans = c.getAllPlans(countryCode, s.Attributes.StripeAccountCountry)
	} else {
		allPlans = c.getAllPlans(countryCode, ente.DefaultStripeAccountCountry)
	}
	subProductID := s.ProductID
	for _, plan := range allPlans {
		if s.PaymentProvider == ente.Stripe && subProductID == plan.StripeID {
			return plan, nil
		} else if s.PaymentProvider == ente.PlayStore && subProductID == plan.AndroidID {
			return plan, nil
		} else if s.PaymentProvider == ente.AppStore && subProductID == plan.IOSID {
			return plan, nil
		} else if (s.PaymentProvider == ente.BitPay || s.PaymentProvider == ente.Paypal) && subProductID == plan.ID {
			return plan, nil
		}
	}
	if s.ProductID == ente.FreePlanProductID || s.ProductID == ente.FamilyPlanProductID {
		return ente.BillingPlan{Period: ente.PeriodYear}, nil
	}

	// If request has a different `countryCode` because the user is traveling, and we're unable to find a plan for that country,
	// fallback to the previous logic for finding a plan.
	plan, _, err := c.getPlanWithCountry(s)
	if err != nil {
		return ente.BillingPlan{}, stacktrace.Propagate(err, "")
	}
	return plan, nil
}
