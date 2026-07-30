package user

import (
	"encoding/base64"

	"github.com/ente/museum/ente"
	enteJWT "github.com/ente/museum/ente/jwt"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/crypto"
	"github.com/ente/stacktrace"
	"github.com/gin-contrib/requestid"
	"github.com/gin-gonic/gin"
	"github.com/sirupsen/logrus"
)

func (c *UserController) GetDeleteChallengeToken(ctx *gin.Context) (*ente.DeleteChallengeResponse, error) {
	userID := auth.GetUserID(ctx.Request.Header)
	user, err := c.UserRepo.Get(userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	keyAttributes, err := c.UserRepo.GetKeyAttributes(userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	logger := logrus.WithFields(logrus.Fields{
		"user_id":    userID,
		"user_email": user.Email,
		"req_id":     requestid.Get(ctx),
		"req_ctx":    "request_self_delete",
	})
	logger.Info("User initiated self-delete")
	subscription, err := c.BillingController.GetSubscription(ctx, userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	/* todo: add check to see if there's pending abuse report or if user's master password
	was changed in last X days.
	*/
	shouldNotifyDiscord := subscription.ProductID != ente.FreePlanProductID
	if shouldNotifyDiscord {
		go c.DiscordController.NotifyAccountDelete(user.ID, string(subscription.PaymentProvider), subscription.ProductID)
	}
	token, err := c.GetJWTToken(userID, enteJWT.DELETE_ACCOUNT)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	encryptedToken, err := crypto.GetEncryptedTokenNative(base64.StdEncoding.EncodeToString([]byte(token)), keyAttributes.PublicKey)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}

	apps, err := c.UserAuthRepo.GetAppsForUser(userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &ente.DeleteChallengeResponse{
		EncryptedChallenge: &encryptedToken,
		AllowDelete:        true,
		Apps:               apps,
	}, nil
}

func (c *UserController) SelfDeleteAccount(ctx *gin.Context, req ente.DeleteAccountRequest) (*ente.DeleteAccountResponse, error) {
	userID := auth.GetUserID(ctx.Request.Header)
	claim, err := c.ValidateJWTToken(req.Challenge, enteJWT.DELETE_ACCOUNT)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to validate jwt token")
	}
	if claim.UserID != userID {
		return nil, stacktrace.Propagate(ente.ErrPermissionDenied, "jwtToken belongs to different user")
	}
	user, err := c.UserRepo.Get(userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	_, err = c.BillingController.GetSubscription(ctx, userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	logger := logrus.WithFields(logrus.Fields{
		"user_id":    userID,
		"user_email": user.Email,
		"req_id":     requestid.Get(ctx),
		"req_ctx":    "self_account_deletion",
	})
	resp, err := c.HandleAccountDeletion(ctx, userID, logger)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	// Update reason, ignore failure in updating reason
	updateErr := c.UserRepo.UpdateDeleteFeedback(userID, req.GetReasonAttr())
	if updateErr != nil {
		logger.WithError(updateErr).Error("failed to update delete feedback")
	}
	return resp, nil
}
