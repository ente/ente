package user

import (
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"strings"
	t "time"

	"github.com/ente/museum/pkg/utils/random"

	"github.com/ente/museum/pkg/utils/config"
	"github.com/ente/museum/pkg/utils/network"
	"github.com/gin-contrib/requestid"
	"github.com/spf13/viper"

	"github.com/ente/museum/ente"
	emailCtrl "github.com/ente/museum/pkg/controller/email"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/crypto"
	emailUtil "github.com/ente/museum/pkg/utils/email"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"

	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
)

type HardCodedOTTEmail struct {
	Email string
	Value string
}

type HardCodedOTT struct {
	Emails            []HardCodedOTTEmail
	LocalDomainSuffix string
	LocalDomainValue  string
}

type signUpState int

const (
	signUpStateNoAccount signUpState = iota
	signUpStateIncomplete
	signUpStateComplete
)

func ReadHardCodedOTTFromConfig() HardCodedOTT {
	emails := make([]HardCodedOTTEmail, 0)
	emailsSlice := viper.GetStringSlice("internal.hardcoded-ott.emails")
	for _, entry := range emailsSlice {
		xs := strings.Split(entry, ",")
		if len(xs) == 2 && xs[0] != "" && xs[1] != "" {
			emails = append(emails, HardCodedOTTEmail{
				Email: xs[0],
				Value: xs[1],
			})
		} else {
			log.Errorf("Ignoring malformed internal.hardcoded-ott.emails entry %s", entry)
		}
	}

	localDomainSuffix := ""
	localDomainValue := ""
	if config.IsLocalEnvironment() {
		localDomainSuffix = viper.GetString("internal.hardcoded-ott.local-domain-suffix")
		localDomainValue = viper.GetString("internal.hardcoded-ott.local-domain-value")
	}

	return HardCodedOTT{
		Emails:            emails,
		LocalDomainSuffix: localDomainSuffix,
		LocalDomainValue:  localDomainValue,
	}
}

func hardcodedOTTForEmail(hardCodedOTT HardCodedOTT, email string) string {
	for _, entry := range hardCodedOTT.Emails {
		if email == entry.Email {
			return entry.Value
		}
	}

	if hardCodedOTT.LocalDomainSuffix != "" && strings.HasSuffix(email, hardCodedOTT.LocalDomainSuffix) {
		return hardCodedOTT.LocalDomainValue
	}

	return ""
}

// SendEmailOTT generates and sends an OTT to the provided email address
func (c *UserController) SendEmailOTT(context *gin.Context, email string, purpose string, mobile bool) error {
	if c.OTTSendLimiter.IsGloballyBlocked() {
		return stacktrace.Propagate(ente.ErrTooManyBadRequest, "too many OTT requests")
	}

	shouldSend, err := c.validateSendOTT(context, email, purpose)
	if err != nil {
		return err
	}
	if !shouldSend {
		return nil
	}
	emailHash, err := crypto.GetHash(email, c.HashingKey)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	// check if user has already requested for more than 10 codes in last 10mins
	app := auth.GetApp(context)
	otts, err := c.UserAuthRepo.GetValidOTTs(emailHash, app)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if len(otts) >= OTTActiveCodeLimit {
		alertMsg := fmt.Sprintf("Too many OTT requests for %s in %d minutes",
			emailUtil.GetMaskedEmailWithHint(email),
			OTTValidityDurationInMicroSeconds/(60*1000000))
		go c.DiscordController.NotifyPotentialAbuse(alertMsg)
		return stacktrace.Propagate(ente.ErrTooManyBadRequest, "too many OTT requests")
	}

	decision := c.OTTSendLimiter.Allow(network.GetClientIP(context))
	if decision.alert != "" {
		go c.DiscordController.NotifyPotentialAbuse(decision.alert)
	}
	if !decision.allowed {
		return stacktrace.Propagate(ente.ErrTooManyBadRequest, "too many OTT requests")
	}

	ott, err := random.GenerateSixDigitOtp()
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	// for hard-coded ott, adding  same OTT in db can throw error
	hasHardcodedOTT := false
	if purpose != ente.ChangeEmailOTTPurpose {
		hardCodedOTT := hardcodedOTTForEmail(c.HardCodedOTT, email)
		if hardCodedOTT != "" {
			log.Warn(fmt.Sprintf("returning hardcoded ott for %s", email))
			hasHardcodedOTT = true
			ott = hardCodedOTT
		}
	}

	err = c.UserAuthRepo.AddOTT(emailHash, app, ott, time.Microseconds()+OTTValidityDurationInMicroSeconds)
	if !hasHardcodedOTT {
		// ignore error for AddOTT for hardcode OTT. This is to avoid error when unique OTT check fails at db layer
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		err = emailOTT(app, email, ott, purpose, mobile)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
	} else {
		log.Info("Added hard coded ott for " + email + " : " + ott)
	}
	return nil
}

func (c *UserController) isEmailAlreadyUsed(email string) error {
	_, err := c.UserRepo.GetUserIDWithEmailUnrestricted(email)
	if err == nil {
		// email already owned by a user
		return stacktrace.Propagate(ente.ErrPermissionDenied, "email already belongs to a user")
	}
	if !errors.Is(err, sql.ErrNoRows) {
		// unknown error, rethrow
		return stacktrace.Propagate(err, "")
	}
	return nil
}

func (c *UserController) validateSendOTT(ctx *gin.Context, email string, purpose string) (bool, error) {
	var disclosureErr error
	if purpose == ente.ChangeEmailOTTPurpose {
		if err := c.isEmailAlreadyUsed(email); err != nil {
			if !errors.Is(err, ente.ErrPermissionDenied) {
				return false, err
			}
			disclosureErr = err
		}
	}
	if purpose != ente.ChangeEmailOTTPurpose {
		signupState, err := c.getSignUpState(email)
		if err != nil {
			return false, stacktrace.Propagate(err, "")
		}
		if purpose == ente.SignUpOTTPurpose && viper.GetBool("internal.disable-registration") && signupState != signUpStateComplete {
			return false, stacktrace.Propagate(ente.ErrPermissionDenied, "registration is disabled")
		}
		if purpose == ente.SignUpOTTPurpose && signupState == signUpStateComplete {
			disclosureErr = stacktrace.Propagate(ente.ErrUserAlreadyRegistered, "user has already completed sign up process")
		}
		if purpose == ente.LoginOTTPurpose && signupState == signUpStateNoAccount {
			disclosureErr = stacktrace.Propagate(ente.ErrUserNotRegistered, "user account does not exist")
		}
		if purpose == ente.LoginOTTPurpose && signupState == signUpStateIncomplete {
			disclosureErr = stacktrace.Propagate(ente.ErrUserSignupIncomplete, "user has not completed sign up process")
		}
	}
	// If there is no state-disclosing error, allow the OTT request.
	if disclosureErr == nil {
		return true, nil
	}

	if c.shouldSwallowSendOTTDisclosureError(ctx) {
		return false, nil
	}
	return false, disclosureErr
}

func (c *UserController) shouldSwallowSendOTTDisclosureError(ctx *gin.Context) bool {
	if c.OTTLimiter == nil {
		return false
	}
	limitContext, limitErr := c.OTTLimiter.Get(ctx, "send-ott")
	if limitErr != nil {
		log.WithError(limitErr).Warn("Failed to check send-ott disclosure rate limit")
		return false
	}
	if !limitContext.Reached {
		return false
	}
	if c.DiscordController != nil {
		go c.DiscordController.NotifyPotentialAbuse("swallowing send-ott disclosure error")
	}
	return true
}

// getSignUpState returns the signup state for an email.
// Signup is complete only when both email and key attributes exist.
func (c *UserController) getSignUpState(email string) (signUpState, error) {
	userID, err := c.UserRepo.GetUserIDWithEmailUnrestricted(email)
	if err != nil && errors.Is(err, sql.ErrNoRows) {
		return signUpStateNoAccount, nil
	}
	if err != nil {
		return signUpStateNoAccount, stacktrace.Propagate(err, "")
	}
	_, keyErr := c.UserRepo.GetKeyAttributes(userID)
	if keyErr != nil && errors.Is(keyErr, sql.ErrNoRows) {
		return signUpStateIncomplete, nil
	}
	if keyErr != nil {
		return signUpStateNoAccount, stacktrace.Propagate(keyErr, "")
	}
	return signUpStateComplete, nil
}

func (c *UserController) AddAdminOtt(req ente.AdminOttReq) error {
	emailHash, err := crypto.GetHash(req.Email, c.HashingKey)
	if err != nil {
		log.WithError(err).Error("Failed to get hash")
		return nil
	}
	err = c.UserAuthRepo.AddOTT(emailHash, req.App, req.Code, req.ExpiryTime)
	if err != nil {
		log.WithError(err).Error("Failed to add ott")
		return stacktrace.Propagate(err, "")
	}
	return nil
}

// verifyEmailOtt should be deprecated in favor of verifyEmailOttWithSession once clients are updated.
func (c *UserController) verifyEmailOtt(context *gin.Context, email string, ott string) error {
	ott = strings.TrimSpace(ott)
	app := auth.GetApp(context)
	emailHash, err := crypto.GetHash(email, c.HashingKey)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	wrongAttempt, err := c.UserAuthRepo.GetMaxWrongAttempts(emailHash, app)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	if wrongAttempt >= OTTWrongAttemptLimit {
		msg := fmt.Sprintf("Too many wrong ott verification attemp for app %s", app)
		go c.DiscordController.NotifyPotentialAbuse(msg)
		return stacktrace.Propagate(ente.ErrTooManyBadRequest, "User needs to wait before active ott are expired")
	}

	otts, err := c.UserAuthRepo.GetValidOTTs(emailHash, app)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if len(otts) < 1 {
		return stacktrace.Propagate(ente.ErrExpiredOTT, "")
	}
	isValidOTT := false
	for _, validOTT := range otts {
		if ott == validOTT {
			isValidOTT = true
		}
	}
	if !isValidOTT {
		if err = c.UserAuthRepo.RecordWrongAttemptForActiveOtt(emailHash, app); err != nil {
			log.WithError(err).Warn("Failed to track wrong attempt")
		}
		return stacktrace.Propagate(ente.ErrIncorrectOTT, "")
	}
	removed, err := c.UserAuthRepo.RemoveOTT(emailHash, ott, app)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if !removed {
		return stacktrace.Propagate(ente.ErrExpiredOTT, "")
	}
	return nil
}

// VerifyEmail validates that the OTT provided in the request is valid for the
// provided email address and if yes returns the users credentials
func (c *UserController) VerifyEmail(context *gin.Context, request ente.EmailVerificationRequest) (ente.EmailAuthorizationResponse, error) {
	email := emailUtil.NormalizeEmail(request.Email)
	err := c.verifyEmailOtt(context, email, request.OTT)
	if err != nil {
		return ente.EmailAuthorizationResponse{}, stacktrace.Propagate(err, "")
	}
	return c.onVerificationSuccess(context, email, request.Source)
}

// ChangeEmail validates that the OTT provided in the request is valid for the
// provided email address and if yes updates the user's existing email address
func (c *UserController) ChangeEmail(ctx *gin.Context, request ente.EmailVerificationRequest) error {
	email := emailUtil.NormalizeEmail(request.Email)
	err := c.verifyEmailOtt(ctx, email, request.OTT)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	return c.UpdateEmail(ctx, auth.GetUserID(ctx.Request.Header), email)
}

// UpdateEmail updates the email address of the user with the provided userID
func (c *UserController) UpdateEmail(ctx *gin.Context, userID int64, email string) error {
	email = emailUtil.NormalizeEmail(email)

	_, err := c.UserRepo.GetUserIDWithEmailUnrestricted(email)
	if err == nil {
		// email already owned by a user
		return stacktrace.Propagate(ente.ErrPermissionDenied, "")
	}
	if !errors.Is(err, sql.ErrNoRows) {
		// unknown error, rethrow
		return stacktrace.Propagate(err, "")
	}
	user, err := c.UserRepo.Get(userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	oldEmail := user.Email
	encryptedEmail, err := crypto.Encrypt(email, c.SecretEncryptionKey)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	emailHash, err := crypto.GetHash(email, c.HashingKey)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	err = c.UserRepo.UpdateEmail(userID, encryptedEmail, emailHash)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	c.touchContactsAfterEmailUpdate(ctx, userID)
	_ = emailUtil.SendTemplatedEmail([]string{user.Email}, "ente", "team@ente.com",
		ente.EmailChangedSubject, ente.EmailChangedTemplate, map[string]interface{}{
			"NewEmail": email,
		}, nil)

	err = c.BillingController.UpdateBillingEmail(userID, email)
	if err != nil {
		log.WithError(err).
			WithFields(log.Fields{
				"req_id":  requestid.Get(ctx),
				"user_id": userID,
			}).Error("stripe update email failed")
	}

	// Unsubscribe the old email, subscribe the new one.
	//
	// Note that resubscribing the same email after it has been unsubscribed
	// once works fine.
	//
	// See also: Do not block on mailing list errors
	go func() {
		if err := c.MailingListsController.Unsubscribe(oldEmail); err != nil {
			log.WithError(err).WithFields(log.Fields{
				"user_id": userID,
				"email":   oldEmail,
			}).Error("mailing list unsubscribe failed")
		}
		if err := c.MailingListsController.Subscribe(email); err != nil {
			log.WithError(err).WithFields(log.Fields{
				"user_id": userID,
				"email":   email,
			}).Error("mailing list subscribe failed")
		}
	}()

	return nil
}

func (c *UserController) touchContactsAfterEmailUpdate(ctx *gin.Context, userID int64) {
	if c.ContactRepo == nil {
		return
	}
	if touchErr := c.ContactRepo.TouchContactsForContactUser(ctx, userID); touchErr != nil {
		log.WithError(touchErr).
			WithFields(log.Fields{
				"req_id":  requestid.Get(ctx),
				"user_id": userID,
			}).
			Error("failed to touch contacts after email update")
	}
}

// Logout removes the token from the cache and database.
// known issue: the token may be still cached in other instances till the expiry time (10min), JWTs might remain too
func (c *UserController) Logout(ctx *gin.Context) error {
	token := auth.GetToken(ctx)
	userID := auth.GetUserID(ctx.Request.Header)
	return c.TerminateSession(userID, token)
}

// GetActiveSessions returns the list of active tokens for userID
func (c *UserController) GetActiveSessions(context *gin.Context, userID int64) ([]ente.Session, error) {
	tokens, err := c.UserAuthRepo.GetActiveSessions(userID, auth.GetApp(context))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return tokens, nil
}

const (
	StorageWarningDeletionScheduledCode    = "ACCOUNT_SCHEDULED_FOR_DELETION"
	StorageWarningDeletionScheduledMessage = "Access to this account has been restricted because its Ente Photos and Ente Locker data is scheduled for deletion. If you think this was a mistake, please reply to this email."
)

func shouldEnforceStorageWarningDeletionLoginBlock(app ente.App) bool {
	return app == ente.Photos || app == ente.Locker
}

func storageWarningDeletionScheduledError() error {
	return stacktrace.Propagate(&ente.ApiError{
		Code:           StorageWarningDeletionScheduledCode,
		Message:        StorageWarningDeletionScheduledMessage,
		HttpStatusCode: http.StatusForbidden,
	}, "storage warning deletion scheduled")
}

func (c *UserController) alertStorageWarningDeletionScheduledLoginBlock(userID int64, app ente.App) {
	log.WithFields(log.Fields{
		"user_id": userID,
		"app":     app,
		"code":    StorageWarningDeletionScheduledCode,
	}).Warn("blocked login due to storage warning scheduled deletion")

	if c.DiscordController != nil {
		discordController := c.DiscordController
		go discordController.NotifyThrottled(
			fmt.Sprintf("🔒 Storage warning login block hit: user_id=%d app=%s", userID, app),
			15*t.Minute,
		)
	}
}

func (c *UserController) ensureStorageWarningDeletionLoginAllowed(userID int64, app ente.App) error {
	if c.NotificationHistoryRepo == nil || !shouldEnforceStorageWarningDeletionLoginBlock(app) {
		return nil
	}
	deletionScheduled, err := c.NotificationHistoryRepo.IsStorageWarningDeletionScheduled(userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to read storage warning deletion state")
	}
	if deletionScheduled {
		// Login blocking is terminal-row based. If a daily storage-warning run
		// races with an admin soft-unblock, the terminal row can reappear while
		// the grace window is still active, so login must honor grace directly.
		graceActive, graceUntil, err := c.NotificationHistoryRepo.IsStorageWarningLoginGraceActive(userID, time.Microseconds())
		if err != nil {
			return stacktrace.Propagate(err, "failed to read storage warning login grace")
		}
		if graceActive {
			log.WithFields(log.Fields{
				"user_id":     userID,
				"app":         app,
				"grace_until": graceUntil,
			}).Info("allowing login during storage warning grace")
			return nil
		}
		c.alertStorageWarningDeletionScheduledLoginBlock(userID, app)
		return storageWarningDeletionScheduledError()
	}
	return nil
}

func (c *UserController) ClearStorageWarningDeletionLoginBlock(userID int64) error {
	if c.NotificationHistoryRepo == nil {
		return nil
	}
	return c.NotificationHistoryRepo.ClearStorageWarningDeletionScheduled(userID)
}

func (c *UserController) AddTokenAndNotify(ctx *gin.Context, userID int64, app ente.App, token string, ip string, userAgent string) error {
	if err := c.ensureStorageWarningDeletionLoginAllowed(userID, app); err != nil {
		return err
	}
	err := c.UserAuthRepo.AddToken(userID, app, token, ip, userAgent)
	if err != nil {
		return stacktrace.Propagate(err, "failed to insert token")
	}

	isEmailMFAEnabled, emailMFAErr := c.UserAuthRepo.IsEmailMFAEnabled(ctx, userID)
	if emailMFAErr != nil {
		log.WithError(emailMFAErr).WithField("user_id", userID).Warn("Failed to fetch email MFA status")
	} else if *isEmailMFAEnabled {
		return nil
	}

	clientPackage := ctx.GetHeader("X-Client-Package")
	go func() {
		user, userErr := c.UserRepo.GetUserByIDInternal(userID)
		if userErr != nil {
			log.WithError(userErr).Error("Failed to get user")
			return
		}
		templateData := map[string]interface{}{
			"Date": t.Now().UTC().Format("02 Jan, 2006 15:04"),
		}
		if strings.HasSuffix(emailUtil.NormalizeEmail(user.Email), "@ente.io") {
			appDisplayNames := map[ente.App]string{
				ente.Photos: "Ente Photos",
				ente.Auth:   "Ente Auth",
				ente.Locker: "Ente Locker",
			}
			appName, ok := appDisplayNames[app]
			if !ok {
				appName = "Ente"
			}
			if clientPackage == "io.ente.space.web" {
				appName = "Ente Space"
			}
			device := "Unknown Device"
			if strings.TrimSpace(userAgent) != "" {
				device = network.GetPrettyUA(userAgent)
			}
			templateData["App"] = appName
			templateData["Device"] = device
			templateData["IP"] = ip
		}
		emailSendErr := emailUtil.SendTemplatedEmail([]string{user.Email}, "Ente", "team@ente.com", emailCtrl.LoginSuccessSubject, emailCtrl.LoginSuccessTemplate, templateData, nil)
		if emailSendErr != nil {
			log.WithError(emailSendErr).Error("Failed to send email")
		}
	}()
	return nil
}

// RemoveTokensForApps marks the given app tokens as deleted and evicts them from the auth cache.
func (c *UserController) RemoveTokensForApps(userID int64, apps []ente.App) error {
	if len(apps) == 0 {
		return nil
	}
	if err := c.deleteActiveTokenCacheEntriesForApps(userID, apps); err != nil {
		return err
	}
	if err := c.UserAuthRepo.RemoveTokensForApps(userID, apps); err != nil {
		return stacktrace.Propagate(err, "failed to remove tokens")
	}
	return nil
}

func (c *UserController) RemoveAllTokens(userID int64) error {
	apps, err := c.UserAuthRepo.GetAppsForUser(userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to get user apps")
	}
	if err = c.deleteActiveTokenCacheEntriesForApps(userID, apps); err != nil {
		return err
	}
	if err = c.UserAuthRepo.RemoveAllTokens(userID); err != nil {
		return stacktrace.Propagate(err, "failed to remove tokens")
	}
	return nil
}

// TerminateSession removes the token for a user from cache and database
func (c *UserController) TerminateSession(userID int64, token string) error {
	apps, err := c.UserAuthRepo.GetAppsForUser(userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to get user apps")
	}
	for _, app := range apps {
		c.Cache.Delete(fmt.Sprintf("%s:%s", app, token))
	}
	return stacktrace.Propagate(c.UserAuthRepo.RemoveToken(userID, token), "")
}

// Auth middleware trusts cached app:token entries for up to a minute, so token
// revocation needs to evict those entries as well to take effect immediately.
func (c *UserController) deleteActiveTokenCacheEntriesForApps(userID int64, apps []ente.App) error {
	if len(apps) == 0 {
		return nil
	}
	for _, app := range apps {
		sessions, err := c.UserAuthRepo.GetActiveSessions(userID, app)
		if err != nil {
			return stacktrace.Propagate(err, "failed to get active sessions")
		}
		for _, session := range sessions {
			c.Cache.Delete(fmt.Sprintf("%s:%s", app, session.Token))
		}
	}
	return nil
}

func emailOTT(app ente.App, to string, ott string, purpose string, mobile bool) error {
	var templateName string
	if purpose == ente.ChangeEmailOTTPurpose {
		templateName = ente.ChangeEmailOTTTemplate
	} else {
		if mobile && app == ente.Photos {
			templateName = ente.OTTMobileTemplate
		} else {
			templateName = ente.OTTTemplate
		}
	}
	subject := fmt.Sprintf("Verification code: %s", ott)
	err := emailUtil.SendTemplatedEmail([]string{to}, "Ente", "verify@ente.com",
		subject, templateName, map[string]interface{}{
			"VerificationCode": ott,
		}, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}

// onVerificationSuccess is called when the user has successfully verified their email address.
// source indicates where the user came from.  It can be nil.
func (c *UserController) onVerificationSuccess(context *gin.Context, email string, source *string) (ente.EmailAuthorizationResponse, error) {
	isTwoFactorEnabled := false
	app := auth.GetApp(context)

	userID, err := c.UserRepo.GetUserIDWithEmailUnrestricted(email)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			if viper.GetBool("internal.disable-registration") {
				return ente.EmailAuthorizationResponse{}, stacktrace.Propagate(ente.ErrPermissionDenied, "")
			} else {
				userID, _, err = c.createUser(email, source)
				if err != nil {
					return ente.EmailAuthorizationResponse{}, stacktrace.Propagate(err, "")
				}
			}
		} else {
			return ente.EmailAuthorizationResponse{}, stacktrace.Propagate(err, "")
		}
	} else {
		isTwoFactorEnabled, err = c.UserRepo.IsTwoFactorEnabled(userID)
		if err != nil {
			return ente.EmailAuthorizationResponse{}, err
		}
	}
	hasPasskeys, err := c.UserRepo.HasPasskeys(userID)
	if err != nil {
		return ente.EmailAuthorizationResponse{}, stacktrace.Propagate(err, "")
	}
	var passKeySessionID, twoFactorSessionID, accountsUrl string

	if hasPasskeys {
		accountsUrl, err = c.PasskeyRepo.AccountsURLForUser(userID)
		if err != nil {
			return ente.EmailAuthorizationResponse{}, stacktrace.Propagate(err, "")
		}

		passKeySessionID = auth.GenerateURLSafeRandomString(PassKeySessionIDLength)
		err = c.PasskeyRepo.AddPasskeyTwoFactorSession(userID, passKeySessionID, time.Microseconds()+TwoFactorValidityDurationInMicroSeconds)
		if err != nil {
			return ente.EmailAuthorizationResponse{}, stacktrace.Propagate(err, "")
		}
	}
	if isTwoFactorEnabled {
		twoFactorSessionID = auth.GenerateURLSafeRandomString(TwoFactorSessionIDLength)
		err = c.TwoFactorRepo.AddTwoFactorSession(userID, twoFactorSessionID, time.Microseconds()+TwoFactorValidityDurationInMicroSeconds)
		if err != nil {
			return ente.EmailAuthorizationResponse{}, stacktrace.Propagate(err, "")
		}
	}
	if hasPasskeys && isTwoFactorEnabled {
		return ente.EmailAuthorizationResponse{ID: userID, PasskeySessionID: passKeySessionID, AccountsUrl: accountsUrl, TwoFactorSessionIDV2: twoFactorSessionID}, nil
	} else if hasPasskeys {
		return ente.EmailAuthorizationResponse{ID: userID, PasskeySessionID: passKeySessionID, AccountsUrl: accountsUrl}, nil
	} else if isTwoFactorEnabled {
		return ente.EmailAuthorizationResponse{ID: userID, TwoFactorSessionID: twoFactorSessionID}, nil
	}

	token := auth.GenerateURLSafeRandomString(TokenLength)
	keyAttributes, err := c.UserRepo.GetKeyAttributes(userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			// user creation is pending on key attributes set based on the password.
			// No need to send login notification
			if err := c.ensureStorageWarningDeletionLoginAllowed(userID, app); err != nil {
				return ente.EmailAuthorizationResponse{}, err
			}
			err = c.UserAuthRepo.AddToken(userID, app, token,
				network.GetClientIP(context), context.Request.UserAgent())
			if err != nil {
				return ente.EmailAuthorizationResponse{}, stacktrace.Propagate(err, "")
			}
			return ente.EmailAuthorizationResponse{ID: userID, Token: token}, nil
		} else {
			return ente.EmailAuthorizationResponse{}, stacktrace.Propagate(err, "")
		}
	}
	var encryptedToken string
	encryptedToken, err = crypto.GetEncryptedTokenNative(token, keyAttributes.PublicKey)
	if err != nil {
		return ente.EmailAuthorizationResponse{}, stacktrace.Propagate(err, "")
	}
	err = c.AddTokenAndNotify(context, userID, app, token,
		network.GetClientIP(context), context.Request.UserAgent())
	if err != nil {
		return ente.EmailAuthorizationResponse{}, stacktrace.Propagate(err, "")
	}
	return ente.EmailAuthorizationResponse{
		ID:             userID,
		KeyAttributes:  &keyAttributes,
		EncryptedToken: encryptedToken,
	}, nil

}

func convertStringToBytes(s string) ([]byte, error) {
	b, err := base64.StdEncoding.DecodeString(s)
	if err != nil {
		return nil, ente.NewBadRequestWithMessage("invalid base64 encoding")
	}
	return b, nil
}

func convertBytesToString(b []byte) string {
	return base64.StdEncoding.EncodeToString(b)
}
