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

func (c *BillingController) GetStripeAccountCountry(userID int64) (ente.StripeAccountCountry, error) {
	subscription, err := c.BillingRepo.GetUserSubscription(userID)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if subscription.PaymentProvider != ente.Stripe {
		return ente.DefaultStripeAccountCountry, nil
	} else {
		return subscription.Attributes.StripeAccountCountry, nil
	}
}

func (c *BillingController) GetUserPlans(ctx *gin.Context, userID int64) ([]ente.BillingPlan, error) {
	stripeAccountCountry, err := c.GetStripeAccountCountry(userID)
	if err != nil {
		return []ente.BillingPlan{}, stacktrace.Propagate(err, "Failed to get user's country stripe account")
	}
	return c.GetPlansV2(network.GetClientCountry(ctx), stripeAccountCountry), nil

}

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
	if len(redirectURL) > 0 && redirectURL[len(redirectURL)-1:] == "/" {
		redirectURL = redirectURL[:len(redirectURL)-1]
	}
	for _, ar := range whitelistedRedirectURLs {
		if ar == redirectURL {
			return ar, nil
		}
	}
	return "", stacktrace.Propagate(ente.ErrBadRequest, "not a whitelistedRedirectURL- %s", redirectURL)
}

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
	isUpgradingFromFreePlan := currentSubscription.ProductID == ente.FreePlanProductID
	if shouldSkipVerifiedSubscriptionReplacement(currentSubscription, newSubscription, time.Microseconds()) {
		log.WithFields(log.Fields{
			"user_id":                      userID,
			"stored_payment_provider":      currentSubscription.PaymentProvider,
			"stored_product_id":            currentSubscription.ProductID,
			"stored_expiry_time":           currentSubscription.ExpiryTime,
			"verified_payment_provider":    newSubscription.PaymentProvider,
			"verified_product_id":          newSubscription.ProductID,
			"verified_expiry_time":         newSubscription.ExpiryTime,
			"same_original_transaction_id": currentSubscription.OriginalTransactionID == newSubscription.OriginalTransactionID,
		}).Info("Skipping verified subscription replacement")
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

func shouldSkipVerifiedSubscriptionReplacement(currentSubscription ente.Subscription, verifiedSubscription ente.Subscription, now int64) bool {
	effectiveExpiry := verifiedSubscription.ExpiryTime + billing.ProviderToExpiryGracePeriodMap[verifiedSubscription.PaymentProvider]
	isSameSubscription := currentSubscription.PaymentProvider == verifiedSubscription.PaymentProvider &&
		currentSubscription.ProductID == verifiedSubscription.ProductID &&
		(verifiedSubscription.PaymentProvider == ente.PlayStore ||
			currentSubscription.OriginalTransactionID == verifiedSubscription.OriginalTransactionID)
	return effectiveExpiry < now ||
		(currentSubscription.ProductID != ente.FreePlanProductID &&
			isSameSubscription &&
			verifiedSubscription.ExpiryTime < currentSubscription.ExpiryTime)
}

func (c *BillingController) getAllPlans(countryCode string, stripeAccountCountry ente.StripeAccountCountry) []ente.BillingPlan {
	if slices.Contains(billing.CountriesInEU, countryCode) {
		countryCode = "EU"
	}
	countryWisePlans := c.BillingPlansPerAccount[stripeAccountCountry]
	if plans, found := countryWisePlans[countryCode]; found {
		return plans
	}
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
	if subscription.ProductID == ente.FreePlanProductID {
		billingLogger.Info("user on free plan")
		return true, nil
	}
	if subscription.ProductID == "" {
		return false, stacktrace.NewError("unexpected product id %s", subscription.ProductID)
	}
	isCancelled = subscription.Attributes.IsCancelled
	if subscription.PaymentProvider == ente.Stripe {
		err = c.StripeController.CancelSubAndDeleteCustomer(subscription, billingLogger)
		if err != nil {
			return false, stacktrace.Propagate(err, "")
		}
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

	// The request country may differ from the subscription country while traveling.
	plan, _, err := c.getPlanWithCountry(s)
	if err != nil {
		return ente.BillingPlan{}, stacktrace.Propagate(err, "")
	}
	return plan, nil
}
