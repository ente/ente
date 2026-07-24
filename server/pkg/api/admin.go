package api

import (
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"github.com/ente/museum/pkg/controller/emergency"
	"github.com/ente/museum/pkg/controller/remotestore"
	"github.com/ente/museum/pkg/repo/authenticator"

	"github.com/ente/museum/pkg/controller/family"

	bonusEntity "github.com/ente/museum/ente/storagebonus"
	"github.com/ente/museum/pkg/repo/storagebonus"

	gTime "time"

	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/controller/discord"
	storagebonusCtrl "github.com/ente/museum/pkg/controller/storagebonus"
	"github.com/ente/museum/pkg/controller/user"
	"github.com/ente/museum/pkg/utils/auth"
	emailUtil "github.com/ente/museum/pkg/utils/email"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/gin-contrib/requestid"
	"github.com/sirupsen/logrus"

	"github.com/ente/museum/pkg/utils/crypto"
	"github.com/ente/stacktrace"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/gin-gonic/gin"
)

// AdminHandler exposes request handlers for all admin related requests
type AdminHandler struct {
	QueueRepo              *repo.QueueRepository
	UserRepo               *repo.UserRepository
	CollectionRepo         *repo.CollectionRepository
	AuthenticatorRepo      *authenticator.Repository
	UserAuthRepo           *repo.UserAuthRepository
	FileRepo               *repo.FileRepository
	BillingRepo            *repo.BillingRepository
	StorageBonusRepo       *storagebonus.Repository
	BillingController      *controller.BillingController
	UserController         *user.UserController
	EmergencyController    *emergency.Controller
	FamilyController       *family.Controller
	RemoteStoreController  *remotestore.Controller
	MailingListsController *controller.MailingListsController
	DiscordController      *discord.DiscordController
	HashingKey             []byte
	PasskeyController      *controller.PasskeyController
	StorageBonusCtl        *storagebonusCtrl.Controller
}

// Duration for which an admin's token is considered valid
const AdminTokenValidityInMinutes = 10

func (h *AdminHandler) SendMail(c *gin.Context) {
	var req ente.SendEmailRequest
	err := handler.BindJSON(c, &req)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	err = emailUtil.Send(req.To, req.FromName, req.FromEmail, req.Subject, req.Body, nil)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

func (h *AdminHandler) SubscribeMail(c *gin.Context) {
	email := c.Query("email")
	err := h.MailingListsController.Subscribe(email)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

func (h *AdminHandler) UnsubscribeMail(c *gin.Context) {
	email := c.Query("email")
	err := h.MailingListsController.Unsubscribe(email)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

func (h *AdminHandler) GetUsers(c *gin.Context) {
	err := h.isFreshAdminToken(c)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	sinceTime, err := strconv.ParseInt(c.Query("sinceTime"), 10, 64)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	users, err := h.UserRepo.GetAll(sinceTime, time.Microseconds())
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{"users": users})
}

func (h *AdminHandler) GetUser(c *gin.Context) {
	e := emailUtil.NormalizeEmail(c.Query("email"))
	if e == "" {
		id, err := strconv.ParseInt(c.Query("id"), 10, 64)
		if err != nil {
			handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, ""))
			return
		}
		user, err := h.UserRepo.GetUserByIDInternal(id)
		if err != nil {
			handler.Error(c, stacktrace.Propagate(err, ""))
			return
		}
		response := gin.H{
			"user": user,
		}
		h.attachSubscription(c, user.ID, response)
		c.JSON(http.StatusOK, response)
		return
	}
	emailHash, err := crypto.GetHash(e, h.HashingKey)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	user, err := h.UserRepo.GetUserByEmailHash(emailHash)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	user.Email = e
	response := gin.H{
		"user": user,
	}
	h.attachSubscription(c, user.ID, response)
	c.JSON(http.StatusOK, response)
}

func (h *AdminHandler) GetScheduledDeletions(c *gin.Context) {
	items, err := h.UserController.GetScheduledDeletions(c, c.Query("email"))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{"scheduledDeletions": items})
}

func (h *AdminHandler) DeleteUser(c *gin.Context) {
	err := h.isFreshAdminToken(c)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	email := emailUtil.NormalizeEmail(c.Query("email"))
	if email == "" {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "email id is missing"))
		return
	}
	emailHash, err := crypto.GetHash(email, h.HashingKey)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	user, err := h.UserRepo.GetUserByEmailHash(emailHash)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	adminID := auth.GetUserID(c.Request.Header)
	logger := logrus.WithFields(logrus.Fields{
		"user_id":    user.ID,
		"admin_id":   adminID,
		"user_email": email,
		"req_id":     requestid.Get(c),
		"req_ctx":    "account_deletion",
	})

	// todo: (neeraj) refactor this part, currently there's a circular dependency between user and emergency controllers
	removeLegacyErr := h.EmergencyController.HandleAccountDeletion(c, user.ID, logger)
	if removeLegacyErr != nil {
		handler.Error(c, stacktrace.Propagate(removeLegacyErr, ""))
		return
	}
	response, err := h.UserController.HandleAccountDeletion(c, user.ID, logger)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	h.notifyAdminAction(adminID, "deleting account for %d", user.ID)
	c.JSON(http.StatusOK, response)
}

func (h *AdminHandler) isFreshAdminToken(c *gin.Context) error {
	token := auth.GetToken(c)
	creationTime, err := h.UserAuthRepo.GetTokenCreationTime(token)
	if err != nil {
		return err
	}
	if (creationTime + time.MicroSecondsInOneMinute*AdminTokenValidityInMinutes) < time.Microseconds() {
		err = ente.NewBadRequestError(&ente.ApiErrorParams{
			Message: "Token is too old",
		})
		return err
	}
	return nil
}

func (h *AdminHandler) DisableTwoFactor(c *gin.Context) {
	err := h.isFreshAdminToken(c)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	var request ente.DisableTwoFactorRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Bad request"))
		return
	}

	adminID := auth.GetUserID(c.Request.Header)
	h.notifyAdminAction(adminID, "disabling 2FA for account %d", request.UserID)
	logger := logrus.WithFields(logrus.Fields{
		"user_id":  request.UserID,
		"admin_id": adminID,
		"req_id":   requestid.Get(c),
		"req_ctx":  "disable_2fa",
	})
	logger.Info("Initiate disable 2FA")
	err = h.UserController.DisableTwoFactor(request.UserID)
	if err != nil {
		logger.WithError(err).Error("Failed to disable 2FA")
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	logger.Info("2FA successfully disabled")
	c.JSON(http.StatusOK, gin.H{})
}

func (h *AdminHandler) UpdateReferral(c *gin.Context) {
	var request ente.UpdateReferralCodeRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Bad request"))
		return
	}
	adminID := auth.GetUserID(c.Request.Header)
	h.notifyAdminAction(adminID, "updating referral code for %d to %s", request.UserID, request.Code)
	err := h.StorageBonusCtl.UpdateReferralCode(c, request.UserID, request.Code, true)
	if err != nil {
		logrus.WithError(err).Error("Failed to disable 2FA")
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

// RemovePasskeys is an admin API request to disable passkey 2FA for a user account by removing its passkeys.
// This is used when we get a user request to reset their passkeys 2FA when they might've lost access to their devices or synced stores. We verify their identity out of band.
// BY DEFAULT, IF THE USER HAS TOTP BASED 2FA ENABLED, REMOVING PASSKEYS WILL NOT DISABLE TOTP 2FA.
func (h *AdminHandler) RemovePasskeys(c *gin.Context) {
	var request ente.AdminOpsForUserRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Bad request"))
		return
	}

	adminID := auth.GetUserID(c.Request.Header)
	h.notifyAdminAction(adminID, "removing passkeys for account %d", request.UserID)
	logger := logrus.WithFields(logrus.Fields{
		"user_id":  request.UserID,
		"admin_id": adminID,
		"req_id":   requestid.Get(c),
		"req_ctx":  "remove_passkeys",
	})
	logger.Info("Initiate remove passkeys")
	err := h.PasskeyController.RemovePasskey2FA(request.UserID)
	if err != nil {
		logger.WithError(err).Error("Failed to remove passkeys")
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	logger.Info("Passkeys successfully removed")
	c.JSON(http.StatusOK, gin.H{})
}

func (h *AdminHandler) UpdateEmailMFA(c *gin.Context) {
	var request ente.AdminOpsForUserRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Bad request"))
		return
	}
	if request.EmailMFA == nil {
		handler.Error(c, stacktrace.Propagate(ente.NewBadRequestWithMessage("emailMFA is required"), ""))
		return
	}

	adminID := auth.GetUserID(c.Request.Header)
	h.notifyAdminAction(adminID, "updating email mfa (%v) for account %d", *request.EmailMFA, request.UserID)
	logger := logrus.WithFields(logrus.Fields{
		"user_id":  request.UserID,
		"admin_id": adminID,
		"req_id":   requestid.Get(c),
		"req_ctx":  "disable_email_mfa",
	})
	logger.Info("Initiate remove passkeys")
	err := h.UserController.UpdateEmailMFA(c, request.UserID, *request.EmailMFA)
	if err != nil {
		logger.WithError(err).Error("Failed to update email mfa")
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	logger.Info("Email MFA successfully updated")
	c.JSON(http.StatusOK, gin.H{})
}

func (h *AdminHandler) UnblockStorageWarningLogin(c *gin.Context) {
	var request ente.AdminOpsForUserRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Bad request"))
		return
	}

	adminID := auth.GetUserID(c.Request.Header)
	h.notifyAdminAction(adminID, "unblocking storage warning login for account %d", request.UserID)
	logger := logrus.WithFields(logrus.Fields{
		"user_id":  request.UserID,
		"admin_id": adminID,
		"req_id":   requestid.Get(c),
		"req_ctx":  "unblock_storage_warning_login",
	})
	logger.Info("Start unblock storage warning login")
	err := h.UserController.UnblockStorageWarningDeletionLogin(request.UserID, logger)
	if err != nil {
		logger.WithError(err).Error("Failed to unblock storage warning login")
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	logger.Info("Finished unblock storage warning login")
	c.JSON(http.StatusOK, gin.H{})
}

func (h *AdminHandler) AddOtt(c *gin.Context) {
	var request ente.AdminOttReq
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Bad request"))
		return
	}
	if err := request.Validate(); err != nil {
		handler.Error(c, stacktrace.Propagate(ente.NewBadRequestWithMessage(err.Error()), "Bad request"))
		return
	}

	adminID := auth.GetUserID(c.Request.Header)
	h.notifyAdminAction(adminID, "adding custom ott")
	logger := logrus.WithFields(logrus.Fields{
		"user_id":  request.Email,
		"code":     request.Code,
		"admin_id": adminID,
		"req_id":   requestid.Get(c),
		"req_ctx":  "custom_ott",
	})

	err := h.UserController.AddAdminOtt(request)
	if err != nil {
		logger.WithError(err).Error("Failed to add ott")
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	logger.Info("Success added ott")
	c.JSON(http.StatusOK, gin.H{})
}

func (h *AdminHandler) TerminateSession(c *gin.Context) {
	var request ente.LogoutSessionReq
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Bad request"))
		return
	}
	adminID := auth.GetUserID(c.Request.Header)
	h.notifyAdminAction(adminID, "terminating session for user %d", request.UserID)
	err := h.UserController.TerminateSession(request.UserID, request.Token)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

func (h *AdminHandler) UpdateFeatureFlag(c *gin.Context) {
	var request ente.AdminUpdateKeyValueRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Bad request"))
		return
	}
	adminID := auth.GetUserID(c.Request.Header)
	h.notifyAdminAction(adminID, "updating flag:%s to val:%v for %d", request.Key, request.Value, request.UserID)

	logger := logrus.WithFields(logrus.Fields{
		"user_id":  request.UserID,
		"admin_id": adminID,
		"req_id":   requestid.Get(c),
		"req_ctx":  "update_feature_flag",
	})
	logger.Info("Start update")
	err := h.RemoteStoreController.AdminInsertOrUpdate(c, request)
	if err != nil {
		logger.WithError(err).Error("Failed to update flag")
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	logger.Info("successfully updated flag")
	c.JSON(http.StatusOK, gin.H{})
}

func (h *AdminHandler) CloseFamily(c *gin.Context) {

	var request ente.AdminOpsForUserRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Bad request"))
		return
	}

	adminID := auth.GetUserID(c.Request.Header)
	h.notifyAdminAction(adminID, "closing family for account %d", request.UserID)
	logger := logrus.WithFields(logrus.Fields{
		"user_id":  request.UserID,
		"admin_id": adminID,
		"req_id":   requestid.Get(c),
		"req_ctx":  "close_family",
	})
	logger.Info("Start close family")
	err := h.FamilyController.CloseFamily(c, request.UserID)
	if err != nil {
		logger.WithError(err).Error("Failed to close family")
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	logger.Info("Finished close family")
	c.JSON(http.StatusOK, gin.H{})
}

func (h *AdminHandler) UpdateSubscription(c *gin.Context) {
	var r ente.UpdateSubscriptionRequest
	if err := handler.BindJSON(c, &r); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Bad request"))
		return
	}
	r.AdminID = auth.GetUserID(c.Request.Header)
	h.notifyAdminAction(r.AdminID, "updating subscription for user: %d", r.UserID)
	err := h.BillingController.UpdateSubscription(r)
	if err != nil {
		logrus.WithError(err).Error("Failed to update subscription")
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	logrus.Info("Updated subscription")
	c.JSON(http.StatusOK, gin.H{})
}

func (h *AdminHandler) ChangeEmail(c *gin.Context) {
	var r ente.ChangeEmailRequest
	if err := handler.BindJSON(c, &r); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Bad request"))
		return
	}
	adminID := auth.GetUserID(c.Request.Header)
	h.notifyAdminAction(adminID, "updating email for user: %d", r.UserID)
	err := h.UserController.UpdateEmail(c, r.UserID, r.Email)
	if err != nil {
		logrus.WithError(err).Error("Failed to update email")
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	logrus.Info("Updated email")
	c.JSON(http.StatusOK, gin.H{})
}

func (h *AdminHandler) ReQueueItem(c *gin.Context) {
	var r ente.ReQueueItemRequest
	if err := handler.BindJSON(c, &r); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Bad request"))
		return
	}
	adminID := auth.GetUserID(c.Request.Header)
	h.notifyAdminAction(adminID, "requeueing item %d for queue: %s", r.ID, r.QueueName)
	err := h.QueueRepo.RequeueItem(c, r.QueueName, r.ID)
	if err != nil {
		logrus.WithError(err).Error("Failed to re-queue item")
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

func (h *AdminHandler) UpdateBonus(c *gin.Context) {
	var r ente.SupportUpdateBonus
	if err := handler.BindJSON(c, &r); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Bad request"))
		return
	}
	if err := r.Validate(); err != nil {
		handler.Error(c, stacktrace.Propagate(ente.NewBadRequestWithMessage(err.Error()), "Bad request"))
		return
	}
	adminID := auth.GetUserID(c.Request.Header)
	var storage, validTill int64
	if r.Testing {
		storage = r.StorageInMB * 1024 * 1024
		validTill = gTime.Now().Add(gTime.Duration(r.Minute) * gTime.Minute).UnixMicro()
	} else {
		storage = r.StorageInGB * 1024 * 1024 * 1024
		validTill = gTime.Now().AddDate(r.Year, 0, 0).UnixMicro()
	}
	var err error
	bonusType := bonusEntity.BonusType(r.BonusType)
	switch r.Action {
	case ente.ADD:
		err = h.StorageBonusRepo.InsertAddOnBonus(c, bonusType, r.UserID, validTill, storage)
	case ente.UPDATE:
		err = h.StorageBonusRepo.UpdateAddOnBonus(c, bonusType, r.UserID, validTill, storage)
	case ente.REMOVE:
		_, err = h.StorageBonusRepo.RemoveAddOnBonus(c, bonusType, r.UserID)
	}
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	h.notifyAdminAction(adminID, ": User %d %s", r.UserID, r.UpdateLog())
	c.JSON(http.StatusOK, gin.H{})
}

func (h *AdminHandler) RecoverAccount(c *gin.Context) {

	var request ente.RecoverAccountRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Bad request"))
		return
	}
	if request.EmailID == "" || !strings.Contains(request.EmailID, "@") {
		handler.Error(c, stacktrace.Propagate(errors.New("invalid email"), "Bad request"))
		return
	}

	adminID := auth.GetUserID(c.Request.Header)
	h.notifyAdminAction(adminID, "recovering account for %d", request.UserID)
	logger := logrus.WithFields(logrus.Fields{
		"user_id":    request.UserID,
		"admin_id":   adminID,
		"user_email": request.EmailID,
		"req_id":     requestid.Get(c),
		"req_ctx":    "account_recovery",
	})
	logger.Info("Initiate account recovery")
	err := h.UserController.HandleAccountRecovery(c, request)
	if err != nil {
		logger.WithError(err).Error("Failed to recover account")
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	logger.Info("Account successfully recovered")
	c.JSON(http.StatusOK, gin.H{})
}

func (h *AdminHandler) GetEmailHash(c *gin.Context) {
	e := emailUtil.NormalizeEmail(c.Query("email"))
	hash, err := crypto.GetHash(e, h.HashingKey)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{"hash": hash})
}

func (h *AdminHandler) GetEmailsFromHashes(c *gin.Context) {
	var request ente.GetEmailsFromHashesRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	emails, err := h.UserRepo.GetEmailsFromHashes(request.Hashes)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{"emails": emails})
}

type adminAlertContext struct {
	ID          int64
	Email       string
	MaskedEmail string
	HasTOTP     bool
}

func (h *AdminHandler) notifyAdminAction(adminID int64, format string, args ...interface{}) {
	adminCtx, err := h.getAdminAlertContext(adminID)
	adminIdentifier := fmt.Sprintf("%d", adminID)
	if err != nil {
		logrus.WithError(err).WithField("admin_id", adminID).Warn("failed to fetch admin details for admin action alert")
	} else if adminCtx.MaskedEmail != "" {
		adminIdentifier = adminCtx.MaskedEmail
	} else if adminCtx.Email != "" {
		adminIdentifier = adminCtx.Email
	}
	action := fmt.Sprintf(format, args...)
	go h.DiscordController.NotifyAdminAction(fmt.Sprintf("Admin (%s) %s", adminIdentifier, action))
	if err == nil {
		go h.alertIfAdminMissing2FA(adminCtx)
	}
}

func (h *AdminHandler) getAdminAlertContext(adminID int64) (adminAlertContext, error) {
	user, err := h.UserRepo.Get(adminID)
	if err != nil {
		return adminAlertContext{}, stacktrace.Propagate(err, "failed to fetch admin details")
	}
	hasTOTP := user.IsTwoFactorEnabled != nil && *user.IsTwoFactorEnabled
	return adminAlertContext{
		ID:          adminID,
		Email:       user.Email,
		MaskedEmail: emailUtil.GetMaskedEmailWithHint(user.Email),
		HasTOTP:     hasTOTP,
	}, nil
}

func (h *AdminHandler) alertIfAdminMissing2FA(ctx adminAlertContext) {
	if h.PasskeyController == nil {
		return
	}
	passkeys, err := h.PasskeyController.GetPasskeys(ctx.ID)
	if err != nil {
		logrus.WithError(err).WithField("admin_id", ctx.ID).Warn("failed to fetch admin passkeys for alert")
		return
	}
	if len(passkeys) > 0 {
		return
	}
	identifier := ctx.MaskedEmail
	if identifier == "" {
		identifier = ctx.Email
	}
	if identifier == "" {
		identifier = fmt.Sprintf("%d", ctx.ID)
	}
	icon := "⚠️"
	message := "is missing passkey 2FA even though TOTP is enabled. Please register a passkey."
	if !ctx.HasTOTP {
		icon = "🚨"
		message = "does not have TOTP or passkey 2FA enabled. Please protect your account with a passkey"
	}
	h.DiscordController.NotifyAdminAction(
		fmt.Sprintf("%s Admin (%s) %s", icon, identifier, message))
}

func (h *AdminHandler) attachSubscription(ctx *gin.Context, userID int64, response gin.H) {
	subscription, err := h.BillingRepo.GetUserSubscription(userID)
	if err == nil {
		response["subscription"] = subscription
	}
	details, err := h.UserController.GetDetailsV2(ctx, userID, false, ente.Photos)
	if err == nil {
		response["details"] = details
	}
	tokenInfos, err := h.UserAuthRepo.GetUserTokenInfo(userID)
	if err == nil {
		response["tokens"] = tokenInfos
	}
	authEntryCount, err := h.AuthenticatorRepo.GetAuthCodeCount(ctx, userID)
	if err == nil {
		response["authCodes"] = authEntryCount
	}
}
