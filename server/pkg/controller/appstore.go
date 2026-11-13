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

type AppStoreController struct {
	AppStoreClient         appstore.Client
	BillingRepo            *repo.BillingRepository
	FileRepo               *repo.FileRepository
	UserRepo               *repo.UserRepository
	RemoteStoreRepo        *remotestore.Repository
	BillingPlansPerAccount ente.BillingPlansPerAccount
	CommonBillCtrl         *commonbilling.Controller
	DiscordController      *discord.DiscordController
	appStoreSharedPassword string
}

type appStoreTransaction struct {
	receiptInfo      appstore.InApp
	expiryTimeMicros int64
}

func NewAppStoreController(
	plans ente.BillingPlansPerAccount,
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
		BillingPlansPerAccount: plans,
		appStoreSharedPassword: appleSharedSecret,
		CommonBillCtrl:         commonBillCtrl,
		DiscordController:      discordController,
	}
}

var SubsUpdateNotificationTypes = []string{string(appstore.NotificationTypeDidChangeRenewalStatus), string(appstore.NotificationTypeCancel), string(appstore.NotificationTypeDidRevoke)}

func isEnteSandboxEmail(userEmail string) bool {
	normalizedEmail := email.NormalizeEmail(userEmail)
	return strings.HasSuffix(normalizedEmail, "@ente.io") ||
		strings.HasSuffix(normalizedEmail, "@ente.com")
}

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

	if isEnteSandboxEmail(user.Email) {
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

func (c *AppStoreController) HandleNotification(ctx *gin.Context, notification appstore.SubscriptionNotification) error {
	logger := logrus.WithFields(logrus.Fields{
		"req_id": requestid.Get(ctx),
	})
	purchase, err := c.verifyAppStoreSubscription(notification.UnifiedReceipt.LatestReceipt)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	transaction, err := getCurrentAppStoreTransaction(purchase.LatestReceiptInfo)
	if err != nil {
		return err
	}
	latestReceiptInfo := transaction.receiptInfo
	if latestReceiptInfo.TransactionID == latestReceiptInfo.OriginalTransactionID && !slices.Contains(SubsUpdateNotificationTypes, string(notification.NotificationType)) {
		var logMsg = fmt.Sprintf("Ignoring notification of type %s", notification.NotificationType)
		if notification.NotificationType != appstore.NotificationTypeInitialBuy {
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

	if latestReceiptInfo.ProductID == subscription.ProductID && transaction.expiryTimeMicros < subscription.ExpiryTime {
		// Outdated notification, no-op
	} else {
		if latestReceiptInfo.ProductID != subscription.ProductID {
			newStorage, err := c.getAppStoreStorage(latestReceiptInfo.ProductID)
			if err != nil {
				return err
			}
			if newStorage < subscription.Storage {
				canDowngrade, canDowngradeErr := c.CommonBillCtrl.CanDowngradeToGivenStorage(newStorage, subscription.UserID)
				if canDowngradeErr != nil {
					return stacktrace.Propagate(canDowngradeErr, "")
				}
				if !canDowngrade {
					return stacktrace.Propagate(ente.ErrCannotDowngrade, "")
				}
				log.Info("Usage is good")
			}
			newSubscription := ente.Subscription{
				Storage:               newStorage,
				ExpiryTime:            transaction.expiryTimeMicros,
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
			err = c.BillingRepo.UpdateSubscriptionExpiryTime(subscription.ID, transaction.expiryTimeMicros)
			if err != nil {
				return stacktrace.Propagate(err, "")
			}
		}
	}
	err = c.BillingRepo.LogAppStorePush(subscription.UserID, notification, *purchase)
	return stacktrace.Propagate(err, "")
}

func (c *AppStoreController) GetVerifiedSubscription(userID int64, productID string, verificationData string) (ente.Subscription, error) {
	response, err := c.verifyAppStoreSubscription(verificationData)
	if err != nil {
		return ente.Subscription{}, stacktrace.Propagate(err, "")
	}

	if err := c.validateSandboxRequest(context.Background(), string(response.Environment), userID, "subscription verification"); err != nil {
		return ente.Subscription{}, err
	}

	transaction, err := getCurrentAppStoreTransaction(response.LatestReceiptInfo)
	if err != nil {
		return ente.Subscription{}, err
	}
	if transaction.receiptInfo.CancellationDateMS != "" {
		return ente.Subscription{}, stacktrace.Propagate(ente.ErrBadRequest, "App Store entitlement was cancelled")
	}
	storage, err := c.getAppStoreStorage(transaction.receiptInfo.ProductID)
	if err != nil {
		return ente.Subscription{}, err
	}
	if productID != transaction.receiptInfo.ProductID {
		logrus.WithFields(logrus.Fields{
			"requested_product_id": productID,
			"verified_product_id":  transaction.receiptInfo.ProductID,
			"user_id":              userID,
		}).Warn("App Store product differs from verified entitlement")
	}
	return ente.Subscription{
		UserID:                userID,
		ProductID:             transaction.receiptInfo.ProductID,
		Storage:               storage,
		OriginalTransactionID: transaction.receiptInfo.OriginalTransactionID,
		ExpiryTime:            transaction.expiryTimeMicros,
		PaymentProvider:       ente.AppStore,
		Attributes: ente.SubscriptionAttributes{
			LatestVerificationData: verificationData,
		},
	}, nil
}

func (c *AppStoreController) verifyAppStoreSubscription(verificationData string) (*appstore.IAPResponse, error) {
	iapRequest := appstore.IAPRequest{
		ReceiptData:            verificationData,
		Password:               c.appStoreSharedPassword,
		ExcludeOldTransactions: true,
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

func getCurrentAppStoreTransaction(receiptInfo []appstore.InApp) (appStoreTransaction, error) {
	var selected appstore.InApp
	var selectedPurchaseTimeMillis int64
	found := false
	ambiguous := false
	for _, candidate := range receiptInfo {
		purchaseTimeMillis, err := strconv.ParseInt(candidate.PurchaseDateMS, 10, 64)
		if err != nil {
			return appStoreTransaction{}, stacktrace.Propagate(ente.ErrBadRequest, "invalid App Store purchase time")
		}
		if !found || purchaseTimeMillis > selectedPurchaseTimeMillis {
			selected = candidate
			selectedPurchaseTimeMillis = purchaseTimeMillis
			found = true
			ambiguous = false
		} else if purchaseTimeMillis == selectedPurchaseTimeMillis && candidate.TransactionID != selected.TransactionID {
			ambiguous = true
		}
	}
	if ambiguous {
		return appStoreTransaction{}, stacktrace.Propagate(ente.ErrBadRequest, "ambiguous App Store entitlement")
	}
	if !found || selected.ProductID == "" || selected.TransactionID == "" || selected.OriginalTransactionID == "" || selected.IsUpgraded == "true" {
		return appStoreTransaction{}, stacktrace.Propagate(ente.ErrBadRequest, "no current App Store entitlement")
	}
	expiryTimeMillis, err := strconv.ParseInt(selected.ExpiresDateMS, 10, 64)
	if err != nil {
		return appStoreTransaction{}, stacktrace.Propagate(ente.ErrBadRequest, "invalid App Store expiry time")
	}
	return appStoreTransaction{
		receiptInfo:      selected,
		expiryTimeMicros: expiryTimeMillis * 1000,
	}, nil
}

func (c *AppStoreController) getAppStoreStorage(productID string) (int64, error) {
	if productID == "" {
		return 0, stacktrace.Propagate(ente.ErrBadRequest, "unknown App Store product")
	}
	var storage int64
	found := false
	for _, plansPerCountry := range c.BillingPlansPerAccount {
		for _, plans := range plansPerCountry {
			for _, plan := range plans {
				if plan.IOSID == "" || plan.IOSID != productID {
					continue
				}
				if found && storage != plan.Storage {
					return 0, stacktrace.NewError("inconsistent App Store product storage")
				}
				storage = plan.Storage
				found = true
			}
		}
	}
	if !found {
		return 0, stacktrace.Propagate(ente.ErrBadRequest, "unknown App Store product")
	}
	return storage, nil
}
