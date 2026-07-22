package user

import (
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"

	"github.com/ente/museum/ente"
	enteJWT "github.com/ente/museum/ente/jwt"
	"github.com/ente/museum/pkg/utils/crypto"
	"github.com/ente/museum/pkg/utils/email"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/lib/pq"
	"github.com/sirupsen/logrus"
	"github.com/spf13/viper"
)

const (
	accountRecoveryLinkValidityDays                = 7
	accountRecoveryInvalidLinkCode  ente.ErrorCode = "ACCOUNT_RECOVERY_INVALID_LINK"
	accountRecoveryLinkExpiredCode  ente.ErrorCode = "ACCOUNT_RECOVERY_LINK_EXPIRED"
	accountRecoveryEmailInUseCode   ente.ErrorCode = "ACCOUNT_RECOVERY_EMAIL_IN_USE"
	accountRecoveryUnavailableCode  ente.ErrorCode = "ACCOUNT_RECOVERY_UNAVAILABLE"
)

var (
	ErrAccountRecoveryInvalidLink = &ente.ApiError{
		Code:           accountRecoveryInvalidLinkCode,
		Message:        "invalid account recovery link",
		HttpStatusCode: http.StatusBadRequest,
	}
	ErrAccountRecoveryLinkExpired = &ente.ApiError{
		Code:           accountRecoveryLinkExpiredCode,
		Message:        "expired account recovery link",
		HttpStatusCode: http.StatusGone,
	}
	ErrAccountRecoveryEmailInUse = &ente.ApiError{
		Code:           accountRecoveryEmailInUseCode,
		Message:        "account recovery email already in use",
		HttpStatusCode: http.StatusConflict,
	}
	ErrAccountRecoveryUnavailable = &ente.ApiError{
		Code:           accountRecoveryUnavailableCode,
		Message:        "account can no longer be recovered",
		HttpStatusCode: http.StatusGone,
	}
)

func (c *UserController) getAccountRecoveryLink(userID int64, userEmail string) (string, error) {
	recoverToken, err := c.GetJWTTokenForClaim(&enteJWT.WebCommonJWTClaim{
		UserID:     userID,
		ExpiryTime: time.MicrosecondsAfterDays(accountRecoveryLinkValidityDays),
		ClaimScope: enteJWT.RestoreAccount.Ptr(),
		Email:      userEmail,
	})
	if err != nil {
		return "", err
	}
	accountsURL := strings.TrimRight(viper.GetString("apps.accounts"), "/")
	return fmt.Sprintf("%s/recover-account#recoveryToken=%s", accountsURL, url.QueryEscape(recoverToken)), nil
}

func (c *UserController) ValidateSelfAccountRecovery(token string) (ente.AccountRecoveryResponse, error) {
	req, err := c.accountRecoveryRequest(token)
	if err != nil {
		return ente.AccountRecoveryResponse{}, err
	}
	status, err := c.accountRecoveryStatus(req, true)
	if err != nil {
		return ente.AccountRecoveryResponse{}, err
	}
	return ente.AccountRecoveryResponse{Status: status}, nil
}

func (c *UserController) RecoverSelfAccount(ctx *gin.Context, token string) (ente.AccountRecoveryResponse, error) {
	req, err := c.accountRecoveryRequest(token)
	if err != nil {
		return ente.AccountRecoveryResponse{}, err
	}
	status, err := c.recoverAccount(ctx, req, true)
	if err != nil {
		return ente.AccountRecoveryResponse{}, err
	}
	return ente.AccountRecoveryResponse{Status: status}, nil
}

// HandleSelfAccountRecovery keeps the legacy recovery link behavior until all
// previously issued links have expired.
func (c *UserController) HandleSelfAccountRecovery(ctx *gin.Context, token string) error {
	_, err := c.RecoverSelfAccount(ctx, token)
	return err
}

func (c *UserController) accountRecoveryRequest(token string) (ente.RecoverAccountRequest, error) {
	jwtToken, err := c.ValidateJWTToken(token, enteJWT.RestoreAccount)
	if err != nil {
		if errors.Is(err, errJWTExpired) {
			return ente.RecoverAccountRequest{}, stacktrace.Propagate(ErrAccountRecoveryLinkExpired, "failed to validate jwt token")
		}
		return ente.RecoverAccountRequest{}, stacktrace.Propagate(ErrAccountRecoveryInvalidLink, "failed to validate jwt token: %s", err.Error())
	}
	if jwtToken.UserID == 0 || jwtToken.Email == "" {
		return ente.RecoverAccountRequest{}, stacktrace.Propagate(ErrAccountRecoveryInvalidLink, "userID or email is empty")
	}
	return ente.RecoverAccountRequest{UserID: jwtToken.UserID, EmailID: jwtToken.Email}, nil
}

func (c *UserController) accountRecoveryStatus(req ente.RecoverAccountRequest, allowAlreadyRecovered bool) (ente.AccountRecoveryStatus, error) {
	user, err := c.UserRepo.Get(req.UserID)
	if err == nil {
		if allowAlreadyRecovered && strings.EqualFold(email.NormalizeEmail(user.Email), email.NormalizeEmail(req.EmailID)) {
			return ente.AccountRecoveryRecovered, nil
		}
		if !allowAlreadyRecovered {
			return "", stacktrace.Propagate(ente.NewBadRequestError(&ente.ApiErrorParams{
				Message: "account is already recovered or userID is linked to another active account",
			}), "")
		}
		return "", stacktrace.Propagate(ErrAccountRecoveryUnavailable, "userID is linked to another active account")
	}
	if errors.Is(err, sql.ErrNoRows) {
		return "", stacktrace.Propagate(ErrAccountRecoveryUnavailable, "user no longer exists")
	}
	if !errors.Is(err, ente.ErrUserDeleted) {
		return "", stacktrace.Propagate(err, "error while getting the user")
	}

	if _, err := c.UserRepo.GetKeyAttributes(req.UserID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", stacktrace.Propagate(ErrAccountRecoveryUnavailable, "key attributes have been deleted")
		}
		return "", stacktrace.Propagate(err, "failed to get key attributes")
	}

	recoveryEmail := email.NormalizeEmail(req.EmailID)
	if userID, err := c.UserRepo.GetUserIDWithEmailUnrestricted(recoveryEmail); err == nil {
		if userID != req.UserID {
			return "", stacktrace.Propagate(ErrAccountRecoveryEmailInUse, "email is already used by user %d", userID)
		}
	} else if !errors.Is(err, sql.ErrNoRows) {
		return "", stacktrace.Propagate(err, "failed to look up the recovery email")
	}
	return ente.AccountRecoveryReady, nil
}

func (c *UserController) HandleAccountRecovery(ctx *gin.Context, req ente.RecoverAccountRequest) error {
	_, err := c.recoverAccount(ctx, req, false)
	return err
}

func (c *UserController) recoverAccount(ctx *gin.Context, req ente.RecoverAccountRequest, allowAlreadyRecovered bool) (ente.AccountRecoveryStatus, error) {
	logger := logrus.WithFields(logrus.Fields{
		"req_id":  ctx.GetString("req_id"),
		"req_ctx": "account_recovery",
		"email":   req.EmailID,
		"userID":  req.UserID,
	})
	logger.Info("initiating account recovery")

	status, err := c.accountRecoveryStatus(req, allowAlreadyRecovered)
	if err != nil {
		return "", err
	}
	if status == ente.AccountRecoveryRecovered {
		return status, nil
	}

	recoveryEmail := email.NormalizeEmail(req.EmailID)
	encryptedEmail, err := crypto.Encrypt(recoveryEmail, c.SecretEncryptionKey)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	emailHash, err := crypto.GetHash(recoveryEmail, c.HashingKey)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if err := c.UserRepo.UpdateEmail(req.UserID, encryptedEmail, emailHash); err != nil {
		if isEmailHashUniqueConstraint(err) {
			return "", stacktrace.Propagate(ErrAccountRecoveryEmailInUse, "email was claimed while recovering the account")
		}
		return "", stacktrace.Propagate(err, "failed to update email")
	}
	c.touchContactsAfterEmailUpdate(ctx, req.UserID)
	if err := c.DataCleanupRepo.RemoveScheduledDelete(ctx, req.UserID); err != nil {
		logger.WithError(err).Error("failed to remove scheduled delete")
		return "", stacktrace.Propagate(err, "")
	}
	return ente.AccountRecoveryRecovered, nil
}

func isEmailHashUniqueConstraint(err error) bool {
	var pqErr *pq.Error
	return errors.As(err, &pqErr) && pqErr.Code == "23505"
}
