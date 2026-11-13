package user

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"github.com/ente/museum/pkg/controller/collections"
	"github.com/ente/museum/pkg/repo/two_factor_recovery"
	util "github.com/ente/museum/pkg/utils"
	"github.com/ulule/limiter/v3"

	cache2 "github.com/ente/museum/ente/cache"
	"github.com/ente/museum/pkg/controller/discord"
	"github.com/ente/museum/pkg/controller/usercache"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/controller/authsession"
	"github.com/ente/museum/pkg/controller/family"
	"github.com/ente/museum/pkg/repo"
	authenticatorRepo "github.com/ente/museum/pkg/repo/authenticator"
	contactrepo "github.com/ente/museum/pkg/repo/contact"
	"github.com/ente/museum/pkg/repo/datacleanup"
	"github.com/ente/museum/pkg/repo/passkey"
	storageBonusRepo "github.com/ente/museum/pkg/repo/storagebonus"
	"github.com/ente/museum/pkg/utils/billing"
	"github.com/ente/museum/pkg/utils/crypto"
	"github.com/ente/museum/pkg/utils/email"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/patrickmn/go-cache"
	"github.com/sirupsen/logrus"
)

type SpaceAccessResetter interface {
	ResetUserAccess(ctx context.Context, userID int64) error
	RevokeBrowserSessions(ctx context.Context, userID int64) error
	RevokeBrowserSessionsTx(ctx context.Context, tx *sql.Tx, userID int64) error
}

type SpaceAccountDeletionAccessResetter interface {
	ResetAccountDeletionAccess(ctx context.Context, userID int64) error
}

type UserController struct {
	UserRepo                *repo.UserRepository
	TwoFactorRecoveryRepo   *two_factor_recovery.Repository
	UsageRepo               *repo.UsageRepository
	UserAuthRepo            *repo.UserAuthRepository
	UserLookup              controller.UserLookup
	TwoFactorRepo           *repo.TwoFactorRepository
	PasskeyRepo             *passkey.Repository
	StorageBonusRepo        *storageBonusRepo.Repository
	AuthenticatorRepo       *authenticatorRepo.Repository
	FileRepo                *repo.FileRepository
	CollectionRepo          *repo.CollectionRepository
	DataCleanupRepo         *datacleanup.Repository
	NotificationHistoryRepo *repo.NotificationHistoryRepository
	CollectionCtrl          *collections.CollectionController
	BillingRepo             *repo.BillingRepository
	BillingController       *controller.BillingController
	FamilyController        *family.Controller
	DiscordController       *discord.DiscordController
	MailingListsController  *controller.MailingListsController
	PushController          *controller.PushController
	SpaceAccessResetter     SpaceAccessResetter
	ContactRepo             *contactrepo.Repository
	HashingKey              []byte
	SecretEncryptionKey     []byte
	JwtSecret               []byte
	Cache                   *cache.Cache
	HardCodedOTT            HardCodedOTT
	UserCache               *cache2.UserCache
	UserCacheController     *usercache.Controller
	SRPLimiter              *limiter.Limiter
	OTTLimiter              *limiter.Limiter
	OTTSendLimiter          *OTTSendLimiter
}

const (
	OTTValidityDurationInMicroSeconds = 60 * 60 * 1000000

	OTTWrongAttemptLimit = 20

	OTTActiveCodeLimit = 10

	TwoFactorValidityDurationInMicroSeconds = 10 * 60 * 1000000

	TokenLength = 32

	TwoFactorSessionIDLength = 32

	PassKeySessionIDLength = 32

	CryptoPwhashMemLimitInteractive = 67108864
	CryptoPwhashOpsLimitInteractive = 2

	TOTPIssuerORG = "ente"

	AccountDeletedEmailTemplate                       = "account_deleted.html"
	AccountDeletedWithActiveSubscriptionEmailTemplate = "account_deleted_active_sub.html"
	AccountDeletedEmailSubject                        = "Your Ente account has been deleted"
)

func NewUserController(
	userRepo *repo.UserRepository,
	usageRepo *repo.UsageRepository,
	userAuthRepo *repo.UserAuthRepository,
	twoFactorRepo *repo.TwoFactorRepository,
	twoFactorRecoveryRepo *two_factor_recovery.Repository,
	passkeyRepo *passkey.Repository,
	authenticatorRepo *authenticatorRepo.Repository,
	storageBonusRepo *storageBonusRepo.Repository,
	fileRepo *repo.FileRepository,
	collectionController *collections.CollectionController,
	collectionRepo *repo.CollectionRepository,
	dataCleanupRepository *datacleanup.Repository,
	notificationHistoryRepo *repo.NotificationHistoryRepository,
	billingRepo *repo.BillingRepository,
	secretEncryptionKeyBytes []byte,
	hashingKeyBytes []byte,
	authCache *cache.Cache,
	jwtSecretBytes []byte,
	billingController *controller.BillingController,
	familyController *family.Controller,
	discordController *discord.DiscordController,
	userLookup controller.UserLookup,
	mailingListsController *controller.MailingListsController,
	pushController *controller.PushController,
	userCache *cache2.UserCache,
	userCacheController *usercache.Controller,
	contactRepo *contactrepo.Repository,
) *UserController {
	srpLimiter := util.NewRateLimiter("100-H")
	ottLimiter := util.NewRateLimiter("100-H")
	ottSendLimiter := NewOTTSendLimiter()
	return &UserController{
		UserRepo:                userRepo,
		UsageRepo:               usageRepo,
		TwoFactorRecoveryRepo:   twoFactorRecoveryRepo,
		UserAuthRepo:            userAuthRepo,
		UserLookup:              userLookup,
		StorageBonusRepo:        storageBonusRepo,
		TwoFactorRepo:           twoFactorRepo,
		AuthenticatorRepo:       authenticatorRepo,
		PasskeyRepo:             passkeyRepo,
		FileRepo:                fileRepo,
		CollectionCtrl:          collectionController,
		CollectionRepo:          collectionRepo,
		DataCleanupRepo:         dataCleanupRepository,
		NotificationHistoryRepo: notificationHistoryRepo,
		BillingRepo:             billingRepo,
		SecretEncryptionKey:     secretEncryptionKeyBytes,
		HashingKey:              hashingKeyBytes,
		Cache:                   authCache,
		JwtSecret:               jwtSecretBytes,
		BillingController:       billingController,
		FamilyController:        familyController,
		DiscordController:       discordController,
		MailingListsController:  mailingListsController,
		PushController:          pushController,
		ContactRepo:             contactRepo,
		HardCodedOTT:            ReadHardCodedOTTFromConfig(),
		UserCache:               userCache,
		UserCacheController:     userCacheController,
		SRPLimiter:              srpLimiter,
		OTTLimiter:              ottLimiter,
		OTTSendLimiter:          ottSendLimiter,
	}
}

func (c *UserController) GetAttributes(userID int64) (ente.KeyAttributes, error) {
	return c.UserRepo.GetKeyAttributes(userID)
}

func (c *UserController) SetAttributes(userID int64, request ente.SetUserAttributesRequest) error {
	_, err := c.UserRepo.GetKeyAttributes(userID)
	if err == nil {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "key attributes are already set")
	}
	if request.KeyAttributes.MemLimit <= 0 || request.KeyAttributes.OpsLimit <= 0 {
		// note for curious soul in the future
		_ = fmt.Sprintf("Older clients were not passing these values, so server used %d & %d as ops and memLimit",
			CryptoPwhashOpsLimitInteractive, CryptoPwhashMemLimitInteractive)
		return stacktrace.Propagate(ente.ErrBadRequest, "mem or ops limit should be > 0")
	}
	err = c.UserRepo.SetKeyAttributes(userID, request.KeyAttributes)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}

func (c *UserController) UpdateEmailMFA(context *gin.Context, userID int64, isEnabled bool) error {
	if !isEnabled {
		isSrpSetupDone, err := c.UserAuthRepo.IsSRPSetupDone(context, userID)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		if !isSrpSetupDone {
			return stacktrace.Propagate(ente.NewConflictError("SRP setup incomplete"), "can not disable email MFA before SRP is setup")
		}
	}
	return c.UserAuthRepo.UpdateEmailMFA(context, userID, isEnabled)
}

func (c *UserController) SetRecoveryKey(userID int64, request ente.SetRecoveryKeyRequest) error {
	keyAttr, keyErr := c.UserRepo.GetKeyAttributes(userID)
	if keyErr != nil {
		return stacktrace.Propagate(keyErr, "User keys setup is not completed")
	}
	if keyAttr.RecoveryKeyEncryptedWithMasterKey != "" {
		return stacktrace.Propagate(errors.New("recovery key is already set"), "")
	}
	err := c.UserRepo.SetRecoveryKeyAttributes(userID, request)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}

func (c *UserController) GetPublicKey(requesterUserID int64, email string) (string, error) {
	userID, err := c.UserLookup.LookupUserID(requesterUserID, email)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	key, err := c.UserRepo.GetPublicKey(userID)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	return key, nil
}

func (c *UserController) GetPublicKeys(requesterUserID int64, emails []string) ([]string, error) {
	if len(emails) == 0 {
		return nil, stacktrace.Propagate(ente.ErrBadRequest, "emails are required")
	}
	if len(emails) > ente.MaxPublicKeyBatchSize {
		return nil, stacktrace.Propagate(ente.ErrBatchSizeTooLarge, "")
	}

	seen := make(map[string]struct{}, len(emails))
	for _, value := range emails {
		normalizedEmail := email.NormalizeEmail(value)
		if normalizedEmail == "" {
			return nil, stacktrace.Propagate(ente.ErrBadRequest, "email is required")
		}
		if _, ok := seen[normalizedEmail]; ok {
			return nil, stacktrace.Propagate(ente.ErrBadRequest, "duplicate email")
		}
		seen[normalizedEmail] = struct{}{}
	}

	publicKeys := make([]string, 0, len(emails))
	for _, value := range emails {
		publicKey, err := c.GetPublicKey(requesterUserID, value)
		if err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		publicKeys = append(publicKeys, publicKey)
	}
	return publicKeys, nil
}

func (c *UserController) GetTwoFactorStatus(userID int64) (bool, error) {
	isTwoFactorEnabled, err := c.UserRepo.IsTwoFactorEnabled(userID)
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	return isTwoFactorEnabled, nil
}

func (c *UserController) HandleAccountDeletion(ctx *gin.Context, userID int64, logger *logrus.Entry) (*ente.DeleteAccountResponse, error) {
	return c.handleAccountDeletion(ctx, userID, logger, true)
}

func (c *UserController) HandleAutomatedAccountDeletion(ctx context.Context, userID int64, logger *logrus.Entry) (*ente.DeleteAccountResponse, error) {
	return c.handleAccountDeletion(ctx, userID, logger, false)
}

func (c *UserController) ResetUserAccess(ctx context.Context, userID int64, logger *logrus.Entry) error {
	return c.resetUserAccess(ctx, userID, logger, false)
}

func (c *UserController) resetAccountDeletionAccess(ctx context.Context, userID int64, logger *logrus.Entry) error {
	return c.resetUserAccess(ctx, userID, logger, true)
}

func (c *UserController) resetUserAccess(ctx context.Context, userID int64, logger *logrus.Entry, accountDeletion bool) error {
	if c.SpaceAccessResetter != nil {
		logger.Info("reset space access for user")
		var err error
		if accountDeletion {
			if resetter, ok := c.SpaceAccessResetter.(SpaceAccountDeletionAccessResetter); ok {
				err = resetter.ResetAccountDeletionAccess(ctx, userID)
			} else {
				err = c.SpaceAccessResetter.ResetUserAccess(ctx, userID)
			}
		} else {
			err = c.SpaceAccessResetter.ResetUserAccess(ctx, userID)
		}
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
	}

	logger.Info("remove locker and photos tokens for user")
	if err := c.RemoveTokensForApps(userID, []ente.App{ente.Locker, ente.Photos}); err != nil {
		return stacktrace.Propagate(err, "")
	}
	if c.SpaceAccessResetter != nil {
		if err := c.SpaceAccessResetter.RevokeBrowserSessions(ctx, userID); err != nil {
			return stacktrace.Propagate(err, "")
		}
	}

	if err := c.CollectionCtrl.ResetUserSharingAccess(ctx, userID, logger); err != nil {
		return stacktrace.Propagate(err, "")
	}

	if err := c.FamilyController.ResetUserFamilyAccess(ctx, userID, logger); err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}

func (c *UserController) handleAccountDeletion(
	ctx context.Context,
	userID int64,
	logger *logrus.Entry,
	sendDeletionEmail bool,
) (*ente.DeleteAccountResponse, error) {
	isSubscriptionCancelled, err := c.BillingController.HandleAccountDeletion(ctx, userID, logger)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}

	err = c.resetAccountDeletionAccess(ctx, userID, logger)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}

	logger.Info("remove push tokens for user")
	c.PushController.RemoveTokensForUser(userID)

	user, err := c.UserRepo.Get(userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}

	email := user.Email
	// Mailing list failures must not block account deletion.
	go func() {
		if err := c.MailingListsController.Unsubscribe(email); err != nil {
			logger.WithError(err).WithFields(logrus.Fields{
				"user_id": userID,
				"email":   email,
			}).Error("mailing list unsubscribe failed")
		}
	}()

	logger.Info("mark user as deleted and schedule data deletion")
	if err := c.markAccountDeletedAndScheduleCleanup(ctx, userID); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}

	if sendDeletionEmail {
		go c.NotifyAccountDeletion(userID, email, isSubscriptionCancelled)
	}

	return &ente.DeleteAccountResponse{
		IsSubscriptionCancelled: isSubscriptionCancelled,
		UserID:                  userID,
	}, nil

}

func (c *UserController) markAccountDeletedAndScheduleCleanup(ctx context.Context, userID int64) error {
	transaction, err := c.UserRepo.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "failed to start account deletion transaction")
	}
	defer transaction.Rollback()

	emailHash, revokedTokens, err := c.UserRepo.DeleteTx(ctx, transaction, userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if err := c.DataCleanupRepo.InsertTx(ctx, transaction, userID, emailHash); err != nil {
		return stacktrace.Propagate(err, "")
	}
	if err := transaction.Commit(); err != nil {
		return stacktrace.Propagate(err, "failed to commit account deletion")
	}
	authsession.MarkRevoked(c.Cache, revokedTokens)
	return nil
}

func (c *UserController) NotifyAccountDeletion(userID int64, userEmail string, isSubscriptionCancelled bool) {
	template := AccountDeletedEmailTemplate
	if !isSubscriptionCancelled {
		template = AccountDeletedWithActiveSubscriptionEmailTemplate
	}
	accountRecoveryLink, err := c.getAccountRecoveryLink(userID, userEmail)
	if err != nil {
		logrus.WithError(err).Error("failed to generate recover token")
		return
	}

	templateData := make(map[string]interface{})
	templateData["AccountRecoveryLink"] = accountRecoveryLink
	err = email.SendTemplatedEmail([]string{userEmail}, "ente", "team@ente.com",
		AccountDeletedEmailSubject, template, templateData, nil)
	if err != nil {
		logrus.WithError(err).Errorf("Failed to send the account deletion email to %s", userEmail)
	}
}

func (c *UserController) createUser(ctx context.Context, email string, source *string) (int64, ente.Subscription, error) {
	encryptedEmail, err := crypto.Encrypt(email, c.SecretEncryptionKey)
	if err != nil {
		return -1, ente.Subscription{}, stacktrace.Propagate(err, "")
	}
	emailHash, err := crypto.GetHash(email, c.HashingKey)
	if err != nil {
		return -1, ente.Subscription{}, stacktrace.Propagate(err, "")
	}
	transaction, err := c.UserRepo.DB.BeginTx(ctx, nil)
	if err != nil {
		return -1, ente.Subscription{}, stacktrace.Propagate(err, "failed to start user creation transaction")
	}
	defer transaction.Rollback()
	userID, err := c.UserRepo.CreateTx(ctx, transaction, encryptedEmail, emailHash, source)
	if err != nil {
		return -1, ente.Subscription{}, stacktrace.Propagate(err, "")
	}
	if err := c.UsageRepo.CreateTx(ctx, transaction, userID); err != nil {
		return -1, ente.Subscription{}, stacktrace.Propagate(err, "failed to add entry in usage")
	}
	subscription := billing.GetFreeSubscription(userID)
	subscription.ID, err = c.BillingRepo.AddSubscriptionTx(ctx, transaction, subscription)
	if err != nil {
		return -1, ente.Subscription{}, stacktrace.Propagate(err, "")
	}
	if err := transaction.Commit(); err != nil {
		return -1, ente.Subscription{}, stacktrace.Propagate(err, "failed to commit user creation")
	}
	// Mailing list failures must not block user creation.
	go func() {
		if err := c.MailingListsController.Subscribe(email); err != nil {
			logrus.WithError(err).WithFields(logrus.Fields{
				"user_id": userID,
				"email":   email,
			}).Error("mailing list subscribe failed")
		}
	}()
	return userID, subscription, nil
}
