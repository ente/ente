package api

import (
	"database/sql"
	"errors"
	"github.com/ente/museum/pkg/controller/emergency"
	"github.com/gin-contrib/requestid"
	"github.com/sirupsen/logrus"
	"github.com/spf13/viper"
	"net/http"
	"strconv"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/jwt"
	"github.com/ente/museum/pkg/controller/user"
	"github.com/ente/museum/pkg/utils/auth"
	emailUtil "github.com/ente/museum/pkg/utils/email"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// UserHandler exposes request handlers for all user related requests
type UserHandler struct {
	UserController      *user.UserController
	EmergencyController *emergency.Controller
}

// SendOTT generates and sends an OTT to the provided email address
func (h *UserHandler) SendOTT(c *gin.Context) {
	var request ente.SendOTTRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	email := emailUtil.NormalizeEmail(request.Email)
	if len(email) == 0 {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "Email id is missing"))
		return
	}
	err := h.UserController.SendEmailOTT(c, email, request.Purpose, request.Mobile)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	} else {
		c.Status(http.StatusOK)
	}
}

// Logout removes the auth token from (instance) cache &  database.
func (h *UserHandler) Logout(c *gin.Context) {
	err := h.UserController.Logout(c)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

// GetDetailsV2 returns details about the requesting user
func (h *UserHandler) GetDetailsV2(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	fetchMemoryCount, _ := strconv.ParseBool(c.DefaultQuery("memoryCount", "true"))

	enteApp := auth.GetApp(c)

	details, err := h.UserController.GetDetailsV2(c, userID, fetchMemoryCount, enteApp)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, details)
}

// GetAccountDeletionSummary returns counts for data that will be deleted.
func (h *UserHandler) GetAccountDeletionSummary(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	summary, err := h.UserController.GetAccountDeletionSummary(c.Request.Context(), userID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, summary)
}

// GetLockerUsage returns locker usage details for the requesting user.
func (h *UserHandler) GetLockerUsage(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)

	lockerUsage, err := h.UserController.GetLockerUsage(c, userID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, lockerUsage)
}

// SetAttributes sets the attributes for a user
func (h *UserHandler) SetAttributes(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	var request ente.SetUserAttributesRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	if err := request.Validate(); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	err := h.UserController.SetAttributes(userID, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

func (h *UserHandler) UpdateEmailMFA(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	var request ente.UpdateEmailMFA
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	err := h.UserController.UpdateEmailMFA(c, userID, *request.IsEnabled)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

// SetRecoveryKey sets the recovery key attributes for a user.
func (h *UserHandler) SetRecoveryKey(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	var request ente.SetRecoveryKeyRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	err := h.UserController.SetRecoveryKey(userID, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

// GetPublicKey returns the public key of a user
func (h *UserHandler) GetPublicKey(c *gin.Context) {
	publicKey, err := h.UserController.GetPublicKey(auth.GetUserID(c.Request.Header), c.Query("email"))
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"publicKey": publicKey,
	})
}

// GetSessionValidityV2 verifies the user's session token and returns if the user has set their keys or not
func (h *UserHandler) GetSessionValidityV2(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	keyAttributes, err := h.UserController.GetAttributes(userID)
	if err == nil {
		c.JSON(http.StatusOK, gin.H{
			"hasSetKeys":    true,
			"keyAttributes": keyAttributes,
		})
	} else {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusOK, gin.H{
				"hasSetKeys": false,
			})
		} else {
			handler.Error(c, stacktrace.Propagate(err, ""))
		}
	}
}

// VerifyEmail validates that the OTT provided in the request is valid for the
// provided email address and if yes returns the users credentials
func (h *UserHandler) VerifyEmail(c *gin.Context) {
	var request ente.EmailVerificationRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	response, err := h.UserController.VerifyEmail(c, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, response)
}

// ChangeEmail validates that the OTT provided in the request is valid for the
// provided email address and if yes updates the user's existing email address
func (h *UserHandler) ChangeEmail(c *gin.Context) {
	var request ente.EmailVerificationRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	err := h.UserController.ChangeEmail(c, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

// GetTwoFactorStatus returns a user's two factor status
func (h *UserHandler) GetTwoFactorStatus(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	status, err := h.UserController.GetTwoFactorStatus(userID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": status})
}

func (h *UserHandler) GetTwoFactorRecoveryStatus(c *gin.Context) {
	res, err := h.UserController.GetTwoFactorRecoveryStatus(c)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, res)
}

// ConfigurePasskeyRecovery configures the passkey skip challenge for a user. In case the user does not
// have access to passkey, the user can bypass the passkey by providing the recovery key
func (h *UserHandler) ConfigurePasskeyRecovery(c *gin.Context) {
	var request ente.SetPasskeyRecoveryRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	err := h.UserController.ConfigurePasskeyRecovery(c, &request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

// SetupTwoFactor generates a two factor secret and sends it to user to setup his authenticator app with
func (h *UserHandler) SetupTwoFactor(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	response, err := h.UserController.SetupTwoFactor(userID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, response)
}

// EnableTwoFactor handles the two factor activation request after user has setup his two factor by validing a totp request
func (h *UserHandler) EnableTwoFactor(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	var request ente.TwoFactorEnableRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	err := h.UserController.EnableTwoFactor(userID, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

// VerifyTwoFactor handles the two factor validation request
func (h *UserHandler) VerifyTwoFactor(c *gin.Context) {
	var request ente.TwoFactorVerificationRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Failed to bind request"))
		return
	}
	response, err := h.UserController.VerifyTwoFactor(c, request.SessionID, request.Code)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, response)
}

// BeginPasskeyRegistrationCeremony handles the request to begin the passkey registration ceremony
func (h *UserHandler) BeginPasskeyAuthenticationCeremony(c *gin.Context) {
	var request ente.PasskeyTwoFactorBeginAuthenticationCeremonyRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Failed to bind request"))
		return
	}

	userID, err := h.UserController.PasskeyRepo.GetUserIDWithPasskeyTwoFactorSession(request.SessionID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}

	isSessionAlreadyClaimed, err := h.UserController.PasskeyRepo.IsSessionAlreadyClaimed(request.SessionID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}

	if isSessionAlreadyClaimed {
		handler.Error(c, stacktrace.Propagate(&ente.ErrSessionAlreadyClaimed, "Session already claimed"))
		return
	}

	user, err := h.UserController.UserRepo.Get(userID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}

	options, _, ceremonySessionID, err := h.UserController.PasskeyRepo.CreateBeginAuthenticationData(&user)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"options":           options,
		"ceremonySessionID": ceremonySessionID,
	})
}

func (h *UserHandler) FinishPasskeyAuthenticationCeremony(c *gin.Context) {
	var request ente.PasskeyTwoFactorFinishAuthenticationCeremonyRequest
	if err := c.ShouldBindQuery(&request); err != nil {
		handler.Error(c, stacktrace.Propagate(ente.ErrBadRequest, "Failed to bind request: %s", err))
		return
	}

	userID, err := h.UserController.PasskeyRepo.GetUserIDWithPasskeyTwoFactorSession(request.SessionID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}

	user, err := h.UserController.GetUser(userID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}

	err = h.UserController.PasskeyRepo.FinishAuthentication(&user, c.Request, uuid.MustParse(request.CeremonySessionID))
	if err != nil {
		reqID := requestid.Get(c)
		logrus.WithField("req_id", reqID).
			WithField("user_id", userID).
			WithError(err).Error("Failed to finish passkey authentication ceremony")
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}

	response, err := h.UserController.GetKeyAttributeAndToken(c, userID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}

	err = h.UserController.PasskeyRepo.StoreTokenData(request.SessionID, response)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to store token data"))
		return
	}

	c.JSON(http.StatusOK, response)
}

func (h *UserHandler) GetTokenForPasskeySession(c *gin.Context) {
	sessionID := c.Query("sessionID")
	if sessionID == "" {
		handler.Error(c, stacktrace.Propagate(ente.NewBadRequestWithMessage("sessionID is required"), ""))
		return
	}
	response, err := h.UserController.PasskeyRepo.GetTokenData(sessionID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "failed to get token data"))
		return
	}
	c.JSON(http.StatusOK, response)
}

func (h *UserHandler) IsPasskeyRecoveryEnabled(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	response, err := h.UserController.GetKeyAttributeAndToken(c, userID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, response)
}

// DisableTwoFactor disables the two factor authentication for a user
func (h *UserHandler) DisableTwoFactor(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	err := h.UserController.DisableTwoFactor(userID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

// RecoverTwoFactor handles the two factor recovery request by sending the
// recoveryKeyEncryptedTwoFactorSecret for the user to decrypt it and make twoFactor removal api call
func (h *UserHandler) RecoverTwoFactor(c *gin.Context) {
	sessionID := c.Query("sessionID")
	twoFactorType := c.Query("twoFactorType")
	var response *ente.TwoFactorRecoveryResponse
	var err error
	if twoFactorType == "passkey" {
		response, err = h.UserController.GetPasskeyRecoveryResponse(c, sessionID)
	} else {
		response, err = h.UserController.RecoverTwoFactor(sessionID)
	}
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, response)
}

// RemoveTwoFactor handles two factor deactivation request if user lost his device
// by authenticating him using his twoFactorsessionToken and twoFactor secret
func (h *UserHandler) RemoveTwoFactor(c *gin.Context) {
	var request ente.TwoFactorRemovalRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	var response *ente.TwoFactorAuthorizationResponse
	var err error
	if request.TwoFactorType == "passkey" {
		response, err = h.UserController.SkipPasskeyVerification(c, &request)
	} else {
		response, err = h.UserController.RemoveTOTPTwoFactor(c, request.SessionID, request.Secret)
	}
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, response)
}

func (h *UserHandler) ReportEvent(c *gin.Context) {
	var request ente.EventReportRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.Status(http.StatusOK)
}

func (h *UserHandler) GetPaymentToken(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	token, err := h.UserController.GetJWTToken(userID, jwt.PAYMENT)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"paymentToken": token,
	})
}

func (h *UserHandler) GetFamiliesToken(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	token, err := h.UserController.GetJWTToken(userID, jwt.FAMILIES)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"familiesToken": token,
		"familyUrl":     viper.GetString("apps.family"),
	})
}

func (h *UserHandler) GetAccountsToken(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	token, err := h.UserController.GetJWTToken(userID, jwt.ACCOUNTS)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	accountsURL, err := h.UserController.PasskeyRepo.AccountsURLForUser(userID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"accountsToken": token,
		"accountsUrl":   accountsURL,
	})
}

func (h *UserHandler) GetActiveSessions(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	sessions, err := h.UserController.GetActiveSessions(c, userID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"sessions": sessions,
	})
}

// TerminateSession removes the auth token from (instance) cache & database.
func (h *UserHandler) TerminateSession(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	token := c.Query("token")
	err := h.UserController.TerminateSession(userID, token)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

// GetDeleteChallenge responds with flag to indicate if account deletion is enabled.
// When enabled, it returns a challenge/encrypted token which clients need to decrypt
// and send-back while confirming deletion
func (h *UserHandler) GetDeleteChallenge(c *gin.Context) {
	response, err := h.UserController.GetDeleteChallengeToken(c)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, response)
}

// DeleteUser api for deleting a user
func (h *UserHandler) DeleteUser(c *gin.Context) {
	var request ente.DeleteAccountRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Could not bind request params"))
		return
	}
	// todo: (neeraj) refactor this part, currently there's a circular dependency between user and emergency controllers
	removeLegacyErr := h.EmergencyController.HandleAccountDeletion(c, auth.GetUserID(c.Request.Header),
		logrus.WithFields(logrus.Fields{
			"user_id": auth.GetUserID(c.Request.Header),
			"req_id":  requestid.Get(c),
			"req_ctx": "self_account_deletion",
		}))
	if removeLegacyErr != nil {
		handler.Error(c, stacktrace.Propagate(removeLegacyErr, ""))
		return
	}
	response, err := h.UserController.SelfDeleteAccount(c, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, response)
}

func (h *UserHandler) SelfAccountRecovery(c *gin.Context) {
	token := c.Query("token")
	if token == "" {
		handler.Error(c, stacktrace.Propagate(ente.NewBadRequestWithMessage("token missing"), "token is required"))
		return
	}
	err := h.UserController.HandleSelfAccountRecovery(c, token)
	if err != nil {
		logrus.WithError(err).
			WithFields(logrus.Fields{
				"req_id": requestid.Get(c),
			}).Warning("Failed to handle self account recovery")
		c.HTML(http.StatusOK, "account_recovery_error.html", gin.H{})
		return
	}
	c.HTML(http.StatusOK, "account_recovered.html", gin.H{})
}

// GetSRPAttributes returns the SRP attributes for a user
func (h *UserHandler) GetSRPAttributes(c *gin.Context) {
	var request ente.GetSRPAttributesRequest
	if err := c.ShouldBindQuery(&request); err != nil {
		handler.Error(c,
			stacktrace.Propagate(ente.ErrBadRequest, "Request binding failed %s", err))
		return
	}
	response, err := h.UserController.GetSRPAttributes(c, request.Email)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	logrus.WithFields(logrus.Fields{
		"email":       request.Email,
		"srp_user_id": response.SRPUserID,
	}).Info("Sending SRP attributes")
	c.JSON(http.StatusOK, gin.H{"attributes": response})
}

// SetupSRP sets the SRP attributes for a user
func (h *UserHandler) SetupSRP(c *gin.Context) {
	var request ente.SetupSRPRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Request binding failed"))
		return
	}
	userID := auth.GetUserID(c.Request.Header)
	resp, err := h.UserController.SetupSRP(c, userID, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, resp)
}

// CompleteSRPSetup completes the SRP setup for a user
func (h *UserHandler) CompleteSRPSetup(c *gin.Context) {
	var request ente.CompleteSRPSetupRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Request binding failed"))
		return
	}
	resp, err := h.UserController.CompleteSRPSetup(c, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, resp)
}

// UpdateSrpAndKeyAttributes updates the SRP setup for a user and key attributes
func (h *UserHandler) UpdateSrpAndKeyAttributes(c *gin.Context) {
	var request ente.UpdateSRPAndKeysRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Request binding failed"))
		return
	}
	userID := auth.GetUserID(c.Request.Header)
	// default to true
	clearTokens := true
	if request.LogOutOtherDevices != nil {
		clearTokens = *request.LogOutOtherDevices
	}
	resp, err := h.UserController.UpdateSrpAndKeyAttributes(c, userID, request, clearTokens)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, resp)
}

// CreateSRPSession set the SRP A value on the server and returns the SRP B value to the client
func (h *UserHandler) CreateSRPSession(c *gin.Context) {
	var request ente.CreateSRPSessionRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Request binding failed"))
		return
	}
	resp, err := h.UserController.CreateSrpSession(c, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, resp)
}

// VerifySRPSession checks the M1 value to determine if user actually knows the password
func (h *UserHandler) VerifySRPSession(c *gin.Context) {
	var request ente.VerifySRPSessionRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Request binding failed"))
		return
	}
	response, err := h.UserController.VerifySRPSession(c, request)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, response)
}
