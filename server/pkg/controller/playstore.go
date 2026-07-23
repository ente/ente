package controller

import (
	"context"
	"errors"
	"os"

	"github.com/ente/museum/pkg/controller/commonbilling"
	"github.com/ente/museum/pkg/repo/storagebonus"

	"github.com/ente/stacktrace"

	log "github.com/sirupsen/logrus"

	"github.com/awa/go-iap/playstore"
	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/config"
	"github.com/ente/museum/pkg/utils/email"
	"google.golang.org/api/androidpublisher/v3"
)

// PlayStoreController provides abstractions for handling billing on AppStore
type PlayStoreController struct {
	PlayStoreClient        *playstore.Client
	BillingRepo            *repo.BillingRepository
	FileRepo               *repo.FileRepository
	UserRepo               *repo.UserRepository
	StorageBonusRepo       *storagebonus.Repository
	BillingPlansPerCountry ente.BillingPlansPerCountry
	CommonBillCtrl         *commonbilling.Controller
}

// PlayStorePackageName is the package name of the PlayStore item
const PlayStorePackageName = "io.ente.photos"

// Return a new instance of PlayStoreController
func NewPlayStoreController(
	plans ente.BillingPlansPerCountry,
	billingRepo *repo.BillingRepository,
	fileRepo *repo.FileRepository,
	userRepo *repo.UserRepository,
	storageBonusRepo *storagebonus.Repository,
	commonBillCtrl *commonbilling.Controller,
) *PlayStoreController {
	playStoreClient, err := newPlayStoreClient()
	if err != nil {
		log.Fatal(err)
	}
	// We don't do nil checks for playStoreClient in the definitions of these
	// methods - if they're getting called, that means we're not in a test
	// environment and so playStoreClient really should've been there.

	return &PlayStoreController{
		PlayStoreClient:        playStoreClient,
		BillingRepo:            billingRepo,
		FileRepo:               fileRepo,
		UserRepo:               userRepo,
		BillingPlansPerCountry: plans,
		StorageBonusRepo:       storageBonusRepo,
		CommonBillCtrl:         commonBillCtrl,
	}
}

func newPlayStoreClient() (*playstore.Client, error) {
	playStoreCredentialsFile, err := config.CredentialFilePath("pst-service-account.json")
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if playStoreCredentialsFile == "" {
		// Can happen when running locally
		return nil, nil
	}

	jsonKey, err := os.ReadFile(playStoreCredentialsFile)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	playStoreClient, err := playstore.New(jsonKey)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}

	return playStoreClient, nil
}

// HandleNotification handles a PlayStore notification
func (c *PlayStoreController) HandleNotification(notification playstore.DeveloperNotification) error {
	transactionID := notification.SubscriptionNotification.PurchaseToken
	productID := notification.SubscriptionNotification.SubscriptionID
	purchase, err := c.verifySubscription(productID, transactionID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	originalTransactionID := transactionID
	if purchase.LinkedPurchaseToken != "" {
		originalTransactionID = purchase.LinkedPurchaseToken
	}
	subscription, err := c.BillingRepo.GetSubscriptionForTransaction(originalTransactionID, ente.PlayStore)
	if err != nil {
		// First subscription, no user to link to
		log.Warn("Could not find transaction against " + originalTransactionID)
		log.Error(err)
		return nil
	}
	switch notification.SubscriptionNotification.NotificationType {
	case playstore.SubscriptionNotificationTypeExpired:
		user, err := c.UserRepo.Get(subscription.UserID)
		if err != nil {
			if errors.Is(err, ente.ErrUserDeleted) {
				// no-op user has already been deleted
				return nil
			}
			return stacktrace.Propagate(err, "")
		}
		// send deletion email for folks who are either on individual plan or admin of a family plan
		if user.FamilyAdminID == nil || *user.FamilyAdminID == subscription.UserID {
			storage, surpErr := c.StorageBonusRepo.GetPaidAddonSurplusStorage(context.Background(), subscription.UserID)
			if surpErr != nil {
				return stacktrace.Propagate(surpErr, "")
			}
			if storage == nil || *storage <= 0 {
				err = email.SendTemplatedEmail([]string{user.Email}, "ente", "support@ente.com",
					ente.SubscriptionEndedEmailSubject,
					ente.SubscriptionEndedEmailTemplate, map[string]interface{}{}, nil)
				if err != nil {
					return stacktrace.Propagate(err, "")
				}
			} else {
				log.WithField("storage", storage).Info("User has surplus storage, not sending email")
			}
		}
		// TODO: Add cron to delete files of users with expired subscriptions
	case playstore.SubscriptionNotificationTypeAccountHold:
		user, err := c.UserRepo.Get(subscription.UserID)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		err = email.SendTemplatedEmail([]string{user.Email}, "ente", "support@ente.com",
			ente.AccountOnHoldEmailSubject,
			ente.OnHoldTemplate, map[string]interface{}{
				"PaymentProvider": "PlayStore",
			}, nil)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
	case playstore.SubscriptionNotificationTypeCanceled:
		err := c.CommonBillCtrl.OnSubscriptionCancelled(subscription.UserID)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
	}
	if transactionID != originalTransactionID { // Upgrade, Downgrade or Resubscription
		var newPlan ente.BillingPlan
		plans := c.BillingPlansPerCountry["EU"] // Country code is irrelevant since Storage will be the same for a given subscriptionID
		for _, plan := range plans {
			if plan.AndroidID == productID {
				newPlan = plan
				break
			}
		}
		if newPlan.Storage < subscription.Storage { // Downgrade
			canDowngrade, canDowngradeErr := c.CommonBillCtrl.CanDowngradeToGivenStorage(newPlan.Storage, subscription.UserID)
			if canDowngradeErr != nil {
				return stacktrace.Propagate(canDowngradeErr, "")
			}
			if !canDowngrade {
				return stacktrace.Propagate(ente.ErrCannotDowngrade, "")
			}
			log.Info("Usage is good")
		}
		newSubscription := ente.Subscription{
			Storage:               newPlan.Storage,
			ExpiryTime:            purchase.ExpiryTimeMillis * 1000,
			ProductID:             productID,
			PaymentProvider:       ente.AppStore,
			OriginalTransactionID: originalTransactionID,
			Attributes:            ente.SubscriptionAttributes{LatestVerificationData: transactionID},
		}
		err = c.BillingRepo.ReplaceSubscription(
			subscription.ID,
			newSubscription,
		)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		err = c.AcknowledgeSubscription(productID, transactionID)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
	} else {
		err = c.BillingRepo.UpdateSubscriptionExpiryTime(
			subscription.ID, purchase.ExpiryTimeMillis*1000)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
	}
	return c.BillingRepo.LogPlayStorePush(subscription.UserID, notification, *purchase)
}

// GetVerifiedSubscription verifies and returns the verified subscription
func (c *PlayStoreController) GetVerifiedSubscription(userID int64, productID string, verificationData string) (ente.Subscription, error) {
	var s ente.Subscription
	s.UserID = userID
	s.ProductID = productID
	s.PaymentProvider = ente.PlayStore
	s.Attributes.LatestVerificationData = verificationData
	plans := c.BillingPlansPerCountry["EU"] // Country code is irrelevant since Storage will be the same for a given subscriptionID
	response, err := c.verifySubscription(productID, verificationData)
	if err != nil {
		return ente.Subscription{}, stacktrace.Propagate(err, "")
	}
	for _, plan := range plans {
		if plan.AndroidID == productID {
			s.Storage = plan.Storage
			break
		}
	}
	s.OriginalTransactionID = verificationData
	s.ExpiryTime = response.ExpiryTimeMillis * 1000
	return s, nil
}

// AcknowledgeSubscription acknowledges a subscription to PlayStore
func (c *PlayStoreController) AcknowledgeSubscription(subscriptionID string, token string) error {
	req := &androidpublisher.SubscriptionPurchasesAcknowledgeRequest{}
	context := context.Background()
	return c.PlayStoreClient.AcknowledgeSubscription(context, PlayStorePackageName, subscriptionID, token, req)
}

// CancelSubscription cancels a PlayStore subscription
func (c *PlayStoreController) CancelSubscription(subscriptionID string, verificationData string) error {
	context := context.Background()
	return c.PlayStoreClient.CancelSubscription(context, PlayStorePackageName, subscriptionID, verificationData)
}

func (c *PlayStoreController) verifySubscription(subscriptionID string, verificationData string) (*androidpublisher.SubscriptionPurchase, error) {
	context := context.Background()
	return c.PlayStoreClient.VerifySubscription(context, PlayStorePackageName, subscriptionID, verificationData)
}
