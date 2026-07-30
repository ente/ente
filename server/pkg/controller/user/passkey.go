package user

import (
	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"
)

// GetTwoFactorRecoveryStatus returns a user's passkey reset status
func (c *UserController) GetTwoFactorRecoveryStatus(ctx *gin.Context) (*ente.TwoFactorRecoveryStatus, error) {
	userID := auth.GetUserID(ctx.Request.Header)
	return c.TwoFactorRecoveryRepo.GetStatus(userID)
}

func (c *UserController) ConfigurePasskeyRecovery(ctx *gin.Context, req *ente.SetPasskeyRecoveryRequest) error {
	userID := auth.GetUserID(ctx.Request.Header)
	return c.TwoFactorRecoveryRepo.SetPasskeyRecovery(ctx, userID, req)
}

func (c *UserController) GetPasskeyRecoveryResponse(ctx *gin.Context, passKeySessionID string) (*ente.TwoFactorRecoveryResponse, error) {
	userID, err := c.PasskeyRepo.GetUserIDWithPasskeyTwoFactorSession(passKeySessionID)
	if err != nil {
		return nil, err
	}
	recoveryStatus, err := c.TwoFactorRecoveryRepo.GetStatus(userID)
	if err != nil {
		return nil, err
	}
	if !recoveryStatus.IsPasskeyRecoveryEnabled {
		return nil, ente.NewBadRequestWithMessage("Passkey reset is not configured")
	}

	result, err := c.TwoFactorRecoveryRepo.GetPasskeyRecoveryData(ctx, userID)
	if err != nil {
		return nil, err
	}
	if result == nil {
		return nil, ente.NewBadRequestWithMessage("Passkey reset is not configured")
	}
	return result, nil
}

func (c *UserController) SkipPasskeyVerification(context *gin.Context, req *ente.TwoFactorRemovalRequest) (*ente.TwoFactorAuthorizationResponse, error) {
	userID, err := c.PasskeyRepo.GetUserIDWithPasskeyTwoFactorSession(req.SessionID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	exists, err := c.TwoFactorRecoveryRepo.ValidatePasskeyRecoverySecret(userID, req.Secret)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if !exists {
		return nil, stacktrace.Propagate(ente.ErrPermissionDenied, "")
	}
	response, err := c.GetKeyAttributeAndToken(context, userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &response, nil
}
