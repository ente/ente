package controller

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/ente/museum/pkg/controller/commonbilling"
	"github.com/ente/museum/pkg/controller/discord"
	"github.com/ente/museum/pkg/utils/email"
	"github.com/prometheus/common/log"

	"github.com/ente/stacktrace"
	"github.com/gin-contrib/requestid"
	"github.com/gin-gonic/gin"
	"github.com/sirupsen/logrus"
	"github.com/spf13/viper"

	"github.com/awa/go-iap/appstore"
	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/remotestore"
)

// AppStoreController provides abstractions for handling billing on AppStore
type AppStoreController struct {
	AppStoreClient         appstore.Client
	BillingRepo            *repo.BillingRepository
	FileRepo               *repo.FileRepository
	UserRepo               *repo.UserRepository
	RemoteStoreRepo        *remotestore.Repository
	BillingPlansPerCountry ente.BillingPlansPerCountry
	CommonBillCtrl         *commonbilling.Controller
	DiscordController      *discord.DiscordController
	// appStoreSharedPassword is the password to be used to access AppStore APIs
	appStoreSharedPassword string
}

// Return a new instance of AppStoreController
func NewAppStoreController(
	plans ente.BillingPlansPerCountry,
	billingRepo *repo.BillingRepository,
	fileRepo *repo.FileRepository,
	userRepo *repo.UserRepository,
	remoteStoreRepo *remotestore.Repository,
	commonBillCtrl *commonbilling.Controller,
	discordController *discord.DiscordController,
) *AppStoreController {
	appleSharedSecret := viper.GetString("apple.shared-secret")
	return &AppStoreController{
		AppStoreClient:         *appstore.New(),
		BillingRepo:            billingRepo,
		FileRepo:               fileRepo,
		UserRepo:               userRepo,
		RemoteStoreRepo:        remoteStoreRepo,
		BillingPlansPerCountry: plans,
		appStoreSharedPassword: appleSharedSecret,
		CommonBillCtrl:         commonBillCtrl,
		DiscordController:      discordController,
	}
}

var SubsUpdateNotificationTypes = []string{string(appstore.NotificationTypeDidChangeRenewalStatus), string(appstore.NotificationTypeCancel), string(appstore.NotificationTypeDidRevoke)}

// validateSandboxRequest checks if the request is from sandbox environment.
// If sandbox, it sends a Discord alert and returns an error for non-whitelisted users.
func (c *AppStoreController) validateSandboxRequest(ctx context.Context, environment string, userID int64, sandboxContext string) error {
	if environment != "Sandbox" {
		return nil
	}

	user, err := c.UserRepo.GetUserByIDInternal(userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to get user for sandbox validation")
	}

	maskedEmail := email.GetMaskedEmailWithHint(user.Email)
	c.DiscordController.NotifyThrottled(fmt.Sprintf("iOS Sandbox %s for user: %s (userID: %d)",
		sandboxContext, maskedEmail, userID), 10*time.Minute)

	if strings.HasSuffix(email.NormalizeEmail(user.Email), "@ente.io") {
		return nil
	}

	value, err := c.RemoteStoreRepo.GetValue(ctx, userID, string(ente.IsInternalUser))
	if err != nil {
		if !errors.Is(err, sql.ErrNoRows) {
			return stacktrace.Propagate(err, "failed to get internal user flag for sandbox validation")
		}
	} else if value == "true" {
		return nil
	}

	return stacktrace.Propagate(ente.NewInternalError("sandbox request from external user"), "")
}

// HandleNotification handles an AppStore notification
func (c *AppStoreController) HandleNotification(ctx *gin.Context, notification appstore.SubscriptionNotification) error {
	logger := logrus.WithFields(logrus.Fields{
		"req_id": requestid.Get(ctx),
	})
	purchase, err := c.verifyAppStoreSubscription(notification.UnifiedReceipt.LatestReceipt)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	latestReceiptInfo := c.getLatestReceiptInfo(purchase.LatestReceiptInfo)
	if latestReceiptInfo.TransactionID == latestReceiptInfo.OriginalTransactionID && !slices.Contains(SubsUpdateNotificationTypes, string(notification.NotificationType)) {
		var logMsg = fmt.Sprintf("Ignoring notification of type %s", notification.NotificationType)
		if notification.NotificationType != appstore.NotificationTypeInitialBuy {
			// log unexpected notification types
			logger.Error(logMsg)
		} else {
			logger.Info(logMsg)
		}
		// First subscription, no user to link to
		return nil
	}
	subscription, err := c.BillingRepo.GetSubscriptionForTransaction(latestReceiptInfo.OriginalTransactionID, ente.AppStore)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	if err := c.validateSandboxRequest(ctx, string(notification.Environment), subscription.UserID,
		fmt.Sprintf("notification (type: %s)", notification.NotificationType)); err != nil {
		return err
	}

	expiryTimeInMillis, _ := strconv.ParseInt(latestReceiptInfo.ExpiresDate.ExpiresDateMS, 10, 64)
	if latestReceiptInfo.ProductID == subscription.ProductID && expiryTimeInMillis*1000 < subscription.ExpiryTime {
		// Outdated notification, no-op
	} else {
		if latestReceiptInfo.ProductID != subscription.ProductID {
			var newPlan ente.BillingPlan
			plans := c.BillingPlansPerCountry["EU"] // Country code is irrelevant since Storage will be the same for a given subscriptionID
			for _, plan := range plans {
				if plan.IOSID == latestReceiptInfo.ProductID {
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
				ExpiryTime:            expiryTimeInMillis * 1000,
				ProductID:             latestReceiptInfo.ProductID,
				PaymentProvider:       ente.AppStore,
				OriginalTransactionID: latestReceiptInfo.OriginalTransactionID,
				Attributes:            ente.SubscriptionAttributes{LatestVerificationData: notification.UnifiedReceipt.LatestReceipt},
			}
			err = c.BillingRepo.ReplaceSubscription(
				subscription.ID,
				newSubscription,
			)
			if err != nil {
				return stacktrace.Propagate(err, "")
			}
		} else {
			if notification.NotificationType == appstore.NotificationTypeDidChangeRenewalStatus {
				err := c.BillingRepo.UpdateSubscriptionCancellationStatus(subscription.UserID, notification.AutoRenewStatus == "false")
				if err != nil {
					return stacktrace.Propagate(err, "")
				}
			} else if notification.NotificationType == appstore.NotificationTypeCancel || notification.NotificationType == appstore.NotificationTypeDidRevoke {
				err := c.CommonBillCtrl.OnSubscriptionCancelled(subscription.UserID)
				if err != nil {
					return stacktrace.Propagate(err, "")
				}
			}
			err = c.BillingRepo.UpdateSubscriptionExpiryTime(subscription.ID, expiryTimeInMillis*1000)
			if err != nil {
				return stacktrace.Propagate(err, "")
			}
		}
	}
	err = c.BillingRepo.LogAppStorePush(subscription.UserID, notification, *purchase)
	return stacktrace.Propagate(err, "")
}

// GetVerifiedSubscription verifies and returns the verified subscription
func (c *AppStoreController) GetVerifiedSubscription(userID int64, productID string, verificationData string) (ente.Subscription, error) {
	var s ente.Subscription
	s.UserID = userID
	s.ProductID = productID
	s.PaymentProvider = ente.AppStore
	s.Attributes.LatestVerificationData = verificationData
	plans := c.BillingPlansPerCountry["EU"] // Country code is irrelevant since Storage will be the same for a given subscriptionID

	response, err := c.verifyAppStoreSubscription(verificationData)
	if err != nil {
		return ente.Subscription{}, stacktrace.Propagate(err, "")
	}

	if err := c.validateSandboxRequest(context.Background(), string(response.Environment), userID, "subscription verification"); err != nil {
		return ente.Subscription{}, err
	}

	for _, plan := range plans {
		if plan.IOSID == productID {
			s.Storage = plan.Storage
			break
		}
	}
	latestReceiptInfo := c.getLatestReceiptInfo(response.LatestReceiptInfo)
	s.OriginalTransactionID = latestReceiptInfo.OriginalTransactionID
	expiryTime, _ := strconv.ParseInt(latestReceiptInfo.ExpiresDate.ExpiresDateMS, 10, 64)
	s.ExpiryTime = expiryTime * 1000
	return s, nil
}

// VerifyAppStoreSubscription verifies an AppStore subscription
func (c *AppStoreController) verifyAppStoreSubscription(verificationData string) (*appstore.IAPResponse, error) {
	iapRequest := appstore.IAPRequest{
		ReceiptData: verificationData,
		Password:    c.appStoreSharedPassword,
	}
	response := &appstore.IAPResponse{}
	context := context.Background()
	err := c.AppStoreClient.Verify(context, iapRequest, response)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if response.Status != 0 {
		return nil, ente.ErrBadRequest
	}
	return response, nil
}

func (c *AppStoreController) getLatestReceiptInfo(receiptInfo []appstore.InApp) appstore.InApp {
	latestReceiptInfo := receiptInfo[0]
	for _, receiptInfo := range receiptInfo {
		if strings.Compare(latestReceiptInfo.ExpiresDate.ExpiresDateMS, receiptInfo.ExpiresDate.ExpiresDateMS) < 0 {
			latestReceiptInfo = receiptInfo
		}
	}
	return latestReceiptInfo
}
