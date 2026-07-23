package repo

import (
	"database/sql"
	"encoding/json"
	"fmt"

	"github.com/ente/stacktrace"

	"github.com/awa/go-iap/appstore"
	"github.com/awa/go-iap/playstore"
	"github.com/ente/museum/ente"
	"google.golang.org/api/androidpublisher/v3"
)

// BillingRepository defines the methods for inserting, updating and retrieving
// billing related entities from the underlying repository
type BillingRepository struct {
	DB *sql.DB
}

// AddSubscription adds a subscription against a userID
func (repo *BillingRepository) AddSubscription(s ente.Subscription) (int64, error) {
	var subscriptionID int64
	err := repo.DB.QueryRow(`INSERT INTO subscriptions(user_id, storage, original_transaction_id, expiry_time, product_id, payment_provider, attributes) 
			VALUES($1, $2, $3, $4, $5, $6, $7)
			RETURNING subscription_id`, s.UserID, s.Storage,
		s.OriginalTransactionID, s.ExpiryTime, s.ProductID, s.PaymentProvider,
		s.Attributes).Scan(&subscriptionID)
	return subscriptionID, stacktrace.Propagate(err, "")
}

// UpdateSubscriptionExpiryTime updates the expiryTime of a subscription
func (repo *BillingRepository) UpdateSubscriptionExpiryTime(subscriptionID int64, expiryTime int64) error {
	_, err := repo.DB.Exec(`UPDATE subscriptions SET expiry_time = $1 WHERE subscription_id = $2`, expiryTime, subscriptionID)
	return stacktrace.Propagate(err, "")
}

// UpdateSubscriptionCancellationStatus updates whether the user will cancel his subscription on period end
func (repo *BillingRepository) UpdateSubscriptionCancellationStatus(userID int64, status bool) error {
	_, err := repo.DB.Exec(`UPDATE subscriptions SET attributes = jsonb_set(attributes, '{isCancelled}', $1::jsonb) WHERE user_id = $2`, status, userID)
	return stacktrace.Propagate(err, "")
}

// GetUserSubscription returns the last created subscription for a userID
func (repo *BillingRepository) GetUserSubscription(userID int64) (ente.Subscription, error) {
	var s ente.Subscription
	row := repo.DB.QueryRow(`SELECT subscription_id, user_id, product_id, storage, original_transaction_id, expiry_time, payment_provider, attributes FROM subscriptions WHERE user_id = $1`, userID)
	err := row.Scan(&s.ID, &s.UserID, &s.ProductID, &s.Storage, &s.OriginalTransactionID, &s.ExpiryTime, &s.PaymentProvider, &s.Attributes)
	return s, stacktrace.Propagate(err, "")
}

// GetSubscriptionForTransaction returns the subscription for a transactionID within a paymentProvider
func (repo *BillingRepository) GetSubscriptionForTransaction(transactionID string, paymentProvider ente.PaymentProvider) (ente.Subscription, error) {
	var s ente.Subscription
	row := repo.DB.QueryRow(`SELECT subscription_id, user_id, product_id, storage, original_transaction_id, expiry_time, payment_provider, attributes FROM subscriptions WHERE original_transaction_id = $1 AND payment_provider = $2`, transactionID, paymentProvider)
	err := row.Scan(&s.ID, &s.UserID, &s.ProductID, &s.Storage, &s.OriginalTransactionID, &s.ExpiryTime, &s.PaymentProvider, &s.Attributes)
	return s, stacktrace.Propagate(err, "")
}

// UpdateTransactionIDOnDeletion just append `userID:` before original transaction id on account deletion.
// This is to ensure that any subscription update isn't accidently applied to the deleted account and
// if user want to use same subscription in different ente account, they should be able to do that.
func (repo *BillingRepository) UpdateTransactionIDOnDeletion(userID int64) error {
	_, err := repo.DB.Query(`update subscriptions SET original_transaction_id = user_id || ':'  || original_transaction_id where original_transaction_id is not NULL and user_id= $1`, userID)
	return stacktrace.Propagate(err, "")
}

// ReplaceSubscription replaces a subscription with a new one
func (repo *BillingRepository) ReplaceSubscription(subscriptionID int64, s ente.Subscription) error {
	_, err := repo.DB.Exec(`UPDATE subscriptions
		SET storage = $2, original_transaction_id = $3, expiry_time = $4, product_id = $5, payment_provider = $6, attributes = $7, upgraded_at = $8
		WHERE subscription_id = $1`,
		subscriptionID, s.Storage, s.OriginalTransactionID, s.ExpiryTime, s.ProductID, s.PaymentProvider, s.Attributes, s.UpgradedAt)
	return stacktrace.Propagate(err, "")
}

// UpdateSubscription updates a subscription
func (repo *BillingRepository) UpdateSubscription(
	subscriptionID int64,
	storage int64,
	paymentProvider ente.PaymentProvider,
	transactionID string,
	productID string,
	expiryTime int64,
) error {
	_, err := repo.DB.Exec(`UPDATE subscriptions
		SET storage = $2, original_transaction_id = $3, expiry_time = $4, product_id = $5, payment_provider = $6
		WHERE subscription_id = $1`,
		subscriptionID, storage, transactionID, expiryTime, productID, paymentProvider)
	return stacktrace.Propagate(err, "")
}

// LogPlayStorePush logs a notification from PlayStore
func (repo *BillingRepository) LogPlayStorePush(userID int64, notification playstore.DeveloperNotification, verificationResponse androidpublisher.SubscriptionPurchase) error {
	notificationJSON, _ := json.Marshal(notification)
	responseJSON, _ := json.Marshal(verificationResponse)
	_, err := repo.DB.Exec(`INSERT INTO subscription_logs(user_id, payment_provider, notification, verification_response) VALUES($1, $2, $3, $4)`,
		userID, ente.PlayStore, notificationJSON, responseJSON)
	return stacktrace.Propagate(err, "")
}

// LogAppStorePush logs a notification from AppStore
func (repo *BillingRepository) LogAppStorePush(userID int64, notification appstore.SubscriptionNotification, verificationResponse appstore.IAPResponse) error {
	notificationJSON, _ := json.Marshal(notification)
	responseJSON, _ := json.Marshal(verificationResponse)
	_, err := repo.DB.Exec(`INSERT INTO subscription_logs(user_id, payment_provider, notification, verification_response) VALUES($1, $2, $3, $4)`,
		userID, ente.AppStore, notificationJSON, responseJSON)
	return stacktrace.Propagate(err, "")
}

func (repo *BillingRepository) IsUserOnPaidPlan(userID int64) (bool, error) {
	query := `
		SELECT CASE
            WHEN NOT EXISTS (
                SELECT 1
                FROM users u
                WHERE u.user_id = 1
            ) THEN true
            ELSE EXISTS (
                SELECT 1
                FROM users u
                WHERE u.user_id = $1
                AND (
                    EXISTS (
                        SELECT 1
                        FROM subscriptions s
                        WHERE s.user_id = COALESCE(u.family_admin_id, u.user_id)
                        AND s.product_id <> 'free'
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM storage_bonus sb
                        WHERE sb.user_id = COALESCE(u.family_admin_id, u.user_id)
                        AND sb.type NOT IN ('SIGN_UP', 'REFERRAL')
                    )
                )
            )
        END
	`
	var isPaidPlan bool
	err := repo.DB.QueryRow(query, userID).Scan(&isPaidPlan)
	if err != nil {
		return false, fmt.Errorf("error checking paid plan status: %v", err)
	}
	return isPaidPlan, nil
}

// LogStripePush logs a notification from Stripe
func (repo *BillingRepository) LogStripePush(eventLog ente.StripeEventLog) error {
	notificationJSON, _ := json.Marshal(eventLog.Event)
	responseJSON, _ := json.Marshal(eventLog.StripeSubscription)
	_, err := repo.DB.Exec(`INSERT INTO subscription_logs(user_id, payment_provider, notification, verification_response) VALUES($1, $2, $3, $4)`,
		eventLog.UserID, ente.Stripe, notificationJSON, responseJSON)
	return stacktrace.Propagate(err, "")
}

// LogAdminTriggeredSubscriptionUpdate logs a subscription modification by an admin
func (repo *BillingRepository) LogAdminTriggeredSubscriptionUpdate(r ente.UpdateSubscriptionRequest) error {
	requestJSON, _ := json.Marshal(r)
	_, err := repo.DB.Exec(`INSERT INTO subscription_logs(user_id, payment_provider, notification, verification_response) VALUES($1, $2, $3, '{}'::json)`,
		r.UserID, r.PaymentProvider, requestJSON)
	return stacktrace.Propagate(err, "")
}
