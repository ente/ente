package user

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"errors"
	"fmt"
	"github.com/ente/go-srp"
	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/auth"
	emailUtil "github.com/ente/museum/pkg/utils/email"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/sirupsen/logrus"
	mathRand "math/rand"
	"net/http"
	"time"
)

const (
	Srp4096Params                = 4096
	MaxUnverifiedSessionInAnHour = 10
	// Used for nonexistent users to preserve SRP timing and prevent enumeration.
	FakeVerifier = "RNYLOgdzKsbhRWN8OoD05kNpfbqb9uASHYpaLrYLYVemCV0pf4fBgo+25jeu8SaVMQhlkyIF2BgGXX4uzy8Pmwq1ocqt8DsGk0DrlOE1AV9ogaY3myoTjXTQG5dU/hTywylKJYdpWSEyzMMLbWcuO8ldS6uzYXqK+jbfEDDj8k4PqLx1715BPgigNydCbD7/VtwaMhQ8MEygiW/2PbieeqUzuCqEWfwu0uytPM9LiuHH7DT3k2fELFOoPWs3KQAhk6rmM17JOLm8Qvt+xGU6nJZKzTNPxw9o4H4FvlGmsEYUdTP+WPdWpzcton6BowCXKN9G3hZx10OUzBuePHFNKjDlaSLpJXVclLWmza6aDBpjKahayW2UvdQw1tSonyFUjJOanocrPEoHthHUjUGXkeRqcaU4CV9KLQFaHqnHTYc9uJKuYl/tcYoWXuHrZ0cFYRpc6qf/gBCuuwkhTXXsJxTlepe5x0gqgQb7mD5y+dvINks/gpO/3x4T4RkQcyoonsOZv2uLIBr3D6Ede9/aJstIkMh3dTEpDWdw8tEaO7ZjqEwKXVA+/fquJ7P8B3fcIvPy8UZOpwAYtWSPh3OYzijG7WFXu+ajPBqkVI1OBSCYOlTQlPXyrv7myiD8/FXJep5IDPeuJsmGrLPJXBZjPKWR0ISBWol5KTYWE2EllYQ="
)

type sessionRevocationScope int

const (
	revokeOtherSessions sessionRevocationScope = iota
	revokeAllSessions
)

func (c *UserController) SetupSRP(context *gin.Context, userID int64, req ente.SetupSRPRequest) (*ente.SetupSRPResponse, error) {
	srpB, sessionID, err := c.createAndInsertSRPSession(context, req.SrpUserID, req.SRPVerifier, req.SRPA)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	setupID, err := c.UserAuthRepo.InsertTempSRPSetup(context, req, userID, sessionID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to add entry in setup table")
	}

	return &ente.SetupSRPResponse{
		SetupID: *setupID,
		SRPB:    *srpB,
	}, nil
}

func (c *UserController) CompleteSRPSetup(context *gin.Context, req ente.CompleteSRPSetupRequest) (*ente.CompleteSRPSetupResponse, error) {
	userID := auth.GetUserID(context.Request.Header)
	setup, err := c.UserAuthRepo.GetTempSRPSetupEntity(context, req.SetupID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	srpM2, err := c.verifySRPSession(context, setup.Verifier, setup.SessionID, req.SRPM1)
	if err != nil {
		return nil, err
	}
	err = c.UserAuthRepo.InsertSRPAuth(context, userID, setup.SRPUserID, setup.Verifier, setup.Salt)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to add entry in srp auth")
	}
	return &ente.CompleteSRPSetupResponse{
		SetupID: req.SetupID,
		SRPM2:   *srpM2,
	}, nil
}

func (c *UserController) UpdateSrpAndKeyAttributes(context *gin.Context,
	userID int64,
	req ente.UpdateSRPAndKeysRequest,
	shouldClearTokens bool,
) (*ente.UpdateSRPSetupResponse, error) {
	return c.updateSrpAndKeyAttributes(context, userID, req, shouldClearTokens, revokeOtherSessions)
}

func (c *UserController) RecoverSrpAndKeyAttributes(context *gin.Context,
	userID int64,
	req ente.UpdateSRPAndKeysRequest,
	logOutAllSessions bool,
) (*ente.UpdateSRPSetupResponse, error) {
	return c.updateSrpAndKeyAttributes(context, userID, req, logOutAllSessions, revokeAllSessions)
}

func (c *UserController) updateSrpAndKeyAttributes(context *gin.Context,
	userID int64,
	req ente.UpdateSRPAndKeysRequest,
	shouldClearTokens bool,
	revocationScope sessionRevocationScope,
) (*ente.UpdateSRPSetupResponse, error) {
	if err := req.Validate(); err != nil {
		return nil, stacktrace.Propagate(err, "invalid request")
	}
	setup, err := c.UserAuthRepo.GetTempSRPSetupEntity(context, req.SetupID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	srpM2, err := c.verifySRPSession(context, setup.Verifier, setup.SessionID, req.SRPM1)
	if err != nil {
		return nil, err
	}
	if shouldClearTokens && c.SpaceAccessResetter != nil {
		if err = c.SpaceAccessResetter.RevokeBrowserSessions(context, userID); err != nil {
			return nil, err
		}
	}
	err = c.UserAuthRepo.InsertOrUpdateSRPAuthAndKeyAttr(context, userID, *req.UpdateAttributes, setup)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to add entry in srp auth")
	}

	if shouldClearTokens {
		if revocationScope == revokeAllSessions {
			err = c.RemoveAllTokens(userID)
		} else {
			err = c.RemoveAllOtherTokens(userID, auth.GetToken(context))
		}
		if err != nil {
			return nil, err
		}
		if c.SpaceAccessResetter != nil {
			if sweepErr := c.SpaceAccessResetter.RevokeBrowserSessions(context, userID); sweepErr != nil {
				logrus.WithError(sweepErr).WithField("user_id", userID).Warn("failed to sweep space browser sessions after password update")
			}
		}
	} else {
		logrus.WithField("user_id", userID).Info("not clearing tokens")
	}

	return &ente.UpdateSRPSetupResponse{
		SetupID: req.SetupID,
		SRPM2:   *srpM2,
	}, nil
}

func (c *UserController) GetSRPAttributes(context *gin.Context, email string) (*ente.GetSRPAttributesResponse, error) {
	userID, err := c.UserRepo.GetUserIDWithEmailUnrestricted(email)
	if err != nil {
		if !errors.Is(err, sql.ErrNoRows) {
			return nil, stacktrace.Propagate(err, "failed to get user id")
		}
		if limit, limitErr := c.SRPLimiter.Get(context, "get_srp"); limitErr == nil {
			if limit.Reached {
				c.DiscordController.NotifyPotentialAbuse("swallowing missing srp errors")
				return fSrpAttributes(email, c.HashingKey)
			}
		}
		return nil, stacktrace.Propagate(err, "failed to get user")
	}
	srpAttributes, err := c.UserAuthRepo.GetSRPAttributes(userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return srpAttributes, nil
}

func (c *UserController) CreateSrpSession(context *gin.Context, req ente.CreateSRPSessionRequest) (*ente.CreateSRPSessionResponse, error) {
	srpAuthEntity, err := c.UserAuthRepo.GetSRPAuthEntityBySRPUserID(context, req.SRPUserID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return c.fCreateSession(req.SRPUserID.String(), req.SRPA)
		}
		return nil, stacktrace.Propagate(err, "failed to get srp auth entity")
	}
	isEmailMFAEnabled, err := c.UserAuthRepo.IsEmailMFAEnabled(context, srpAuthEntity.UserID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}

	if *isEmailMFAEnabled {
		return nil, stacktrace.Propagate(&ente.ApiError{
			Code:           "EMAIL_MFA_ENABLED",
			Message:        "Email MFA is enabled",
			HttpStatusCode: http.StatusConflict,
		}, "email mfa is enabled")
	}

	srpBBase64, sessionID, err := c.createAndInsertSRPSession(context, req.SRPUserID, srpAuthEntity.Verifier, req.SRPA)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &ente.CreateSRPSessionResponse{
		SRPB:      *srpBBase64,
		SessionID: *sessionID,
	}, nil
}

func (c *UserController) VerifySRPSession(context *gin.Context, req ente.VerifySRPSessionRequest) (*ente.EmailAuthorizationResponse, error) {
	srpAuthEntity, err := c.UserAuthRepo.GetSRPAuthEntityBySRPUserID(context, req.SRPUserID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			_, verifyErr := c.verifySRPSession(context, FakeVerifier, req.SessionID, req.SRPM1)
			return nil, verifyErr
		}
		return nil, stacktrace.Propagate(err, "")
	}
	srpM2, err := c.verifySRPSession(context, srpAuthEntity.Verifier, req.SessionID, req.SRPM1)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	user, err := c.UserRepo.Get(srpAuthEntity.UserID)
	if err != nil {
		return nil, err
	}
	verResponse, err := c.onVerificationSuccess(context, user.Email, nil)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	verResponse.SrpM2 = srpM2
	return &verResponse, nil
}

func (c *UserController) createAndInsertSRPSession(
	gContext *gin.Context,
	srpUserID uuid.UUID,
	srpVerifier string,
	srpA string,
) (*string, *uuid.UUID, error) {
	srpABytes, err := convertStringToBytes(srpA)
	if err != nil {
		return nil, nil, err
	}
	if len(srpABytes) != 512 {
		return nil, nil, ente.NewBadRequestWithMessage("Invalid length for srpA")
	}
	unverifiedSessions, err := c.UserAuthRepo.GetUnverifiedSessionsInLastHour(srpUserID)
	if err != nil {
		return nil, nil, stacktrace.Propagate(err, "")
	}
	if unverifiedSessions >= MaxUnverifiedSessionInAnHour {
		go c.DiscordController.NotifyPotentialAbuse(fmt.Sprintf("Too many unverified sessions for user %s", srpUserID.String()))
		return nil, nil, stacktrace.Propagate(&ente.ApiError{
			Code:           "TOO_MANY_UNVERIFIED_SESSIONS",
			HttpStatusCode: http.StatusTooManyRequests,
		}, "")

	}

	serverSecret := srp.GenKey()
	srpParams := srp.GetParams(Srp4096Params)
	srpVerifierBytes, err := convertStringToBytes(srpVerifier)
	if err != nil {
		return nil, nil, err
	}
	srpServer := srp.NewServer(srpParams, srpVerifierBytes, serverSecret)

	if srpServer == nil {
		return nil, nil, stacktrace.NewError("server is nil")
	}

	srpServer.SetA(srpABytes)
	srpB := srpServer.ComputeB()

	if srpB == nil {
		return nil, nil, stacktrace.NewError("srpB is nil")
	}

	if len(srpB) != 512 {
		return nil, nil, ente.NewBadRequestWithMessage("Invalid length for srpB")
	}

	sessionID, err := c.UserAuthRepo.AddSRPSession(srpUserID, convertBytesToString(serverSecret), srpA)

	if err != nil {
		return nil, nil, stacktrace.Propagate(err, "")
	}

	srpBBase64 := convertBytesToString(srpB)
	return &srpBBase64, &sessionID, nil
}

func (c *UserController) verifySRPSession(ctx context.Context,
	srpVerifier string,
	sessionID uuid.UUID,
	srpM1 string,
) (*string, error) {
	srpM1Bytes, err := convertStringToBytes(srpM1)
	if err != nil {
		return nil, err
	}
	if len(srpM1Bytes) != 32 {
		return nil, ente.NewBadRequestWithMessage(fmt.Sprintf("srpM1 size is %d, expected 32", len(srpM1Bytes)))
	}
	srpSession, err := c.UserAuthRepo.ReserveSrpSessionAttempt(ctx, sessionID, 5)
	if err != nil {
		if !errors.Is(err, sql.ErrNoRows) {
			return nil, stacktrace.Propagate(err, "")
		}
		srpSession, err = c.UserAuthRepo.GetSrpSessionEntity(ctx, sessionID)
		if err != nil {
			// Do not reveal whether the session exists.
			if errors.Is(err, sql.ErrNoRows) {
				// Match normal verification timing.
				time.Sleep(time.Duration(10+mathRand.Intn(20)) * time.Millisecond)
				return nil, stacktrace.Propagate(ente.ErrInvalidPassword, "session not found")
			}
			return nil, stacktrace.Propagate(err, "")
		}
		if srpSession.IsVerified {
			return nil, stacktrace.Propagate(&ente.ApiError{
				Code:           "SESSION_ALREADY_VERIFIED",
				HttpStatusCode: http.StatusGone,
			}, "")
		}
		return nil, stacktrace.Propagate(&ente.ApiError{
			Code:           "TOO_MANY_WRONG_ATTEMPTS",
			HttpStatusCode: http.StatusGone,
		}, "")
	}

	if srpSession.IsFake {
		// Match real-session timing.
		time.Sleep(time.Duration(20+mathRand.Intn(30)) * time.Millisecond)
		return nil, stacktrace.Propagate(ente.ErrInvalidPassword, "fake session verification")
	}

	srpParams := srp.GetParams(Srp4096Params)
	srpVerifierBytes, err := convertStringToBytes(srpVerifier)
	if err != nil {
		return nil, err
	}
	serverKeyBytes, err := convertStringToBytes(srpSession.ServerKey)
	if err != nil {
		return nil, err
	}
	srpServer := srp.NewServer(srpParams, srpVerifierBytes, serverKeyBytes)

	if srpServer == nil {
		return nil, stacktrace.NewError("server is nil")
	}
	srpABytes, err := convertStringToBytes(srpSession.SRP_A)
	if err != nil {
		return nil, err
	}

	srpServer.SetA(srpABytes)

	srpM2Bytes, err := srpServer.CheckM1(srpM1Bytes)

	if err != nil {
		return nil, stacktrace.Propagate(ente.ErrInvalidPassword, "failed to verify srp session")
	}
	claimed, err := c.UserAuthRepo.TrySetSrpSessionVerified(ctx, sessionID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if !claimed {
		return nil, stacktrace.Propagate(&ente.ApiError{
			Code:           "SESSION_ALREADY_VERIFIED",
			HttpStatusCode: http.StatusGone,
		}, "")
	}
	srpM2 := convertBytesToString(srpM2Bytes)
	return &srpM2, nil
}

func fSrpAttributes(email string, hashKey []byte) (*ente.GetSRPAttributesResponse, error) {
	email = emailUtil.NormalizeEmail(email)
	emailHasher := sha256.New()
	emailHasher.Write([]byte("email-salt-purpose-and-uuid"))
	emailHasher.Write([]byte(email))
	emailHasher.Write(hashKey)
	emailHash := emailHasher.Sum(nil)

	kekSaltMaker := sha256.New()
	kekSaltMaker.Write([]byte("kek-salt-purpose"))
	kekSaltMaker.Write([]byte(email))
	kekSaltMaker.Write(hashKey)
	kekSaltHash := kekSaltMaker.Sum(nil)

	uuidBytes := make([]byte, 16)
	copy(uuidBytes, emailHash[:16])
	uuidBytes[6] = (uuidBytes[6] & 0x0f) | 0x40 // Version 4
	uuidBytes[8] = (uuidBytes[8] & 0x3f) | 0x80 // Variant RFC 4122
	uuidStr := fmt.Sprintf("%08x-%04x-%04x-%04x-%012x",
		uuidBytes[:4],
		uuidBytes[4:6],
		uuidBytes[6:8],
		uuidBytes[8:10],
		uuidBytes[10:16])
	memLimit := 1073741824
	opsLimit := 4
	emailVerificationEnabled := false
	if emailHash[16]%2 == 0 {
		memLimit = 268435456
		opsLimit = 16
	}
	if emailHash[16]%5 == 0 {
		emailVerificationEnabled = true
	}
	return &ente.GetSRPAttributesResponse{
		SRPUserID: uuidStr,
		SRPSalt:   convertBytesToString(emailHash[16:32]),
		KekSalt:   convertBytesToString(kekSaltHash[16:32]),
		MemLimit:  memLimit,
		OpsLimit:  opsLimit,

		IsEmailMFAEnabled: emailVerificationEnabled,
	}, nil
}

func (c *UserController) fCreateSession(srpUserID string, srpA string) (*ente.CreateSRPSessionResponse, error) {
	srpABytes, err := convertStringToBytes(srpA)
	if err != nil {
		return nil, err
	}
	if len(srpABytes) != 512 {
		return nil, ente.NewBadRequestWithMessage("Invalid length for srpA")
	}

	// Match the timing variance of a real SRP exchange.
	baseDelay := 30
	variableDelay := mathRand.Intn(50)
	time.Sleep(time.Duration(baseDelay+variableDelay) * time.Millisecond)

	// Match real SRP key and response sizes.
	serverSecret := make([]byte, 64)
	rand.Read(serverSecret)

	srpBBytes := make([]byte, 512)
	rand.Read(srpBBytes)

	userUUID, err := uuid.Parse(srpUserID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to parse srpUserID")
	}

	// Persist fake sessions so verification follows the normal database path.
	sessionID, err := c.UserAuthRepo.AddFakeSRPSession(userUUID, convertBytesToString(serverSecret), srpA)
	if err != nil {
		// If storage fails, still return a response to avoid revealing system errors
		return &ente.CreateSRPSessionResponse{
			SessionID: uuid.New(),
			SRPB:      convertBytesToString(srpBBytes),
		}, nil
	}

	return &ente.CreateSRPSessionResponse{
		SessionID: sessionID,
		SRPB:      convertBytesToString(srpBBytes),
	}, nil
}
