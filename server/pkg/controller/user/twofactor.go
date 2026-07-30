package user

import (
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"image/png"

	"github.com/ente/museum/pkg/utils/network"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/crypto"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/pquerna/otp/totp"
	log "github.com/sirupsen/logrus"
)

// SetupTwoFactor generates a two factor secret and sends it to user to setup his authenticator app with
func (c *UserController) SetupTwoFactor(userID int64) (ente.TwoFactorSecret, error) {
	user, err := c.UserRepo.Get(userID)
	if err != nil {
		return ente.TwoFactorSecret{}, stacktrace.Propagate(err, "")
	}
	if _, keyErr := c.UserRepo.GetKeyAttributes(userID); keyErr != nil {
		return ente.TwoFactorSecret{}, stacktrace.Propagate(keyErr, "User keys setup is not completed")
	}
	key, err := totp.Generate(totp.GenerateOpts{Issuer: TOTPIssuerORG, AccountName: user.Email})
	if err != nil {
		return ente.TwoFactorSecret{}, stacktrace.Propagate(err, "")
	}
	encryptedSecret, err := crypto.Encrypt(key.Secret(), c.SecretEncryptionKey)
	if err != nil {
		return ente.TwoFactorSecret{}, stacktrace.Propagate(err, "")
	}
	secretHash, err := crypto.GetHash(key.Secret(), c.HashingKey)
	if err != nil {
		return ente.TwoFactorSecret{}, stacktrace.Propagate(err, "")
	}
	err = c.TwoFactorRepo.SetTempTwoFactorSecret(userID, encryptedSecret, secretHash, time.Microseconds()+TwoFactorValidityDurationInMicroSeconds)
	if err != nil {
		return ente.TwoFactorSecret{}, stacktrace.Propagate(err, "")
	}
	buf := new(bytes.Buffer)
	img, err := key.Image(200, 200)
	if err != nil {
		return ente.TwoFactorSecret{}, stacktrace.Propagate(err, "")
	}
	err = png.Encode(buf, img)
	if err != nil {
		return ente.TwoFactorSecret{}, stacktrace.Propagate(err, "")
	}
	return ente.TwoFactorSecret{SecretCode: key.Secret(), QRCode: base64.StdEncoding.EncodeToString(buf.Bytes())}, nil
}

// EnableTwoFactor handles the two factor activation request after user has setup his two factor by validing a totp request
func (c *UserController) EnableTwoFactor(userID int64, request ente.TwoFactorEnableRequest) error {
	encryptedSecrets, hashedSecrets, err := c.TwoFactorRepo.GetTempTwoFactorSecret(userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	valid := false
	validSecret := ""
	var validEncryptedSecret ente.EncryptionResult
	var validSecretHash string
	for index, encryptedSecret := range encryptedSecrets {
		secret, err := crypto.Decrypt(encryptedSecret.Cipher, c.SecretEncryptionKey, encryptedSecret.Nonce)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		valid = totp.Validate(request.Code, secret)
		if valid {
			validSecret = secret
			validEncryptedSecret = encryptedSecret
			validSecretHash = hashedSecrets[index]
			break
		}
	}
	if !valid {
		return stacktrace.Propagate(ente.ErrIncorrectTOTP, "")
	}
	err = c.UserRepo.SetTwoFactorSecret(userID, validEncryptedSecret, validSecretHash, request.EncryptedTwoFactorSecret, request.TwoFactorSecretDecryptionNonce)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	err = c.TwoFactorRepo.UpdateTwoFactorStatus(userID, true)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	secretHash, err := crypto.GetHash(validSecret, c.HashingKey)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	err = c.TwoFactorRepo.RemoveTempTwoFactorSecret(secretHash)
	return stacktrace.Propagate(err, "")
}

// VerifyTwoFactor handles the two factor validation request
func (c *UserController) VerifyTwoFactor(context *gin.Context, sessionID string, otp string) (ente.TwoFactorAuthorizationResponse, error) {
	userID, err := c.TwoFactorRepo.GetUserIDWithTwoFactorSession(sessionID)
	if err != nil {
		return ente.TwoFactorAuthorizationResponse{}, stacktrace.Propagate(err, "")
	}
	wrongAttempt, err := c.TwoFactorRepo.GetWrongAttempts(sessionID)
	if err != nil {
		return ente.TwoFactorAuthorizationResponse{}, stacktrace.Propagate(err, "")
	}

	if wrongAttempt >= 10 {
		msg := fmt.Sprintf("Too many wrong two-factor verification attempts for userID: %d", userID)
		go c.DiscordController.NotifyPotentialAbuse(msg)
		return ente.TwoFactorAuthorizationResponse{}, stacktrace.Propagate(ente.ErrTooManyBadRequest, "Too many wrong attempts, please request a new verification session")
	}

	isTwoFactorEnabled, err := c.UserRepo.IsTwoFactorEnabled(userID)
	if err != nil {
		return ente.TwoFactorAuthorizationResponse{}, stacktrace.Propagate(err, "")
	}
	if !isTwoFactorEnabled {
		return ente.TwoFactorAuthorizationResponse{}, stacktrace.Propagate(ente.ErrBadRequest, "")
	}

	secret, err := c.TwoFactorRepo.GetTwoFactorSecret(userID)
	if err != nil {
		return ente.TwoFactorAuthorizationResponse{}, stacktrace.Propagate(err, "")
	}
	valid := totp.Validate(otp, secret)
	if !valid {
		if err = c.TwoFactorRepo.RecordWrongAttempt(sessionID); err != nil {
			log.WithError(err).Warn("Failed to track wrong attempt for two-factor session")
		}
		return ente.TwoFactorAuthorizationResponse{}, stacktrace.Propagate(ente.ErrIncorrectTOTP, "")
	}

	// Try to record OTP atomically - this will fail if already used
	hashData := fmt.Sprintf("%d:%s", userID, otp)
	hash := sha256.Sum256([]byte(hashData))
	otpHash := hex.EncodeToString(hash[:])

	wasNew, err := c.TwoFactorRepo.TryRecordUsedOTPCode(userID, otpHash)
	if err != nil {
		log.WithError(err).Error("Failed to record used OTP code")
		// Continue anyway to not break authentication
	} else if !wasNew {
		// Code was already used - replay attack
		msg := fmt.Sprintf("Replay attack detected for userID: %d - OTP code reused", userID)
		log.Warn(msg)
		go c.DiscordController.NotifyPotentialAbuse(msg)

		if err = c.TwoFactorRepo.RecordWrongAttempt(sessionID); err != nil {
			log.WithError(err).Warn("Failed to track wrong attempt for two-factor session")
		}
		return ente.TwoFactorAuthorizationResponse{}, stacktrace.Propagate(ente.ErrIncorrectTOTP, "OTP code has already been used")
	}

	response, err := c.GetKeyAttributeAndToken(context, userID)
	if err != nil {
		return ente.TwoFactorAuthorizationResponse{}, stacktrace.Propagate(err, "")
	}
	return response, nil
}

// DisableTwoFactor disables the two factor authentication for a user
func (c *UserController) DisableTwoFactor(userID int64) error {
	err := c.TwoFactorRepo.UpdateTwoFactorStatus(userID, false)
	return stacktrace.Propagate(err, "")
}

// RecoverTwoFactor handles the two factor recovery request by sending the
// recoveryKeyEncryptedTwoFactorSecret for the user to decrypt it and make twoFactor removal api call
func (c *UserController) RecoverTwoFactor(sessionID string) (*ente.TwoFactorRecoveryResponse, error) {
	userID, err := c.TwoFactorRepo.GetUserIDWithTwoFactorSession(sessionID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	response, err := c.TwoFactorRepo.GetRecoveryKeyEncryptedTwoFactorSecret(userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &response, nil
}

// RemoveTOTPTwoFactor handles two factor deactivation request if user lost his device
// by authenticating him using his twoFactorsessionToken and twoFactor secret
func (c *UserController) RemoveTOTPTwoFactor(context *gin.Context, sessionID string, secret string) (*ente.TwoFactorAuthorizationResponse, error) {
	userID, err := c.TwoFactorRepo.GetUserIDWithTwoFactorSession(sessionID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	secretHash, err := crypto.GetHash(secret, c.HashingKey)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")

	}
	exists, err := c.TwoFactorRepo.VerifyTwoFactorSecret(userID, secretHash)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")

	}
	if !exists {
		return nil, stacktrace.Propagate(ente.ErrPermissionDenied, "")
	}
	err = c.TwoFactorRepo.UpdateTwoFactorStatus(userID, false)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	response, err := c.GetKeyAttributeAndToken(context, userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &response, nil
}

func (c *UserController) GetKeyAttributeAndToken(context *gin.Context, userID int64) (ente.TwoFactorAuthorizationResponse, error) {
	keyAttributes, err := c.UserRepo.GetKeyAttributes(userID)
	if err != nil {
		return ente.TwoFactorAuthorizationResponse{}, stacktrace.Propagate(err, "")
	}
	token := auth.GenerateURLSafeRandomString(TokenLength)
	encryptedToken, err := crypto.GetEncryptedTokenNative(token, keyAttributes.PublicKey)
	if err != nil {
		return ente.TwoFactorAuthorizationResponse{}, stacktrace.Propagate(err, "")
	}
	err = c.AddTokenAndNotify(context, userID, auth.GetApp(context),
		token, network.GetClientIP(context), context.Request.UserAgent())
	if err != nil {
		return ente.TwoFactorAuthorizationResponse{}, stacktrace.Propagate(err, "")
	}
	return ente.TwoFactorAuthorizationResponse{
		ID:             userID,
		KeyAttributes:  &keyAttributes,
		EncryptedToken: encryptedToken,
	}, nil
}
