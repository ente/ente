package discountcoupon

import (
	"context"
	"fmt"
	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/controller/discord"
	"github.com/ente/museum/pkg/controller/email"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/discountcoupon"
	emailUtil "github.com/ente/museum/pkg/utils/email"
	"github.com/ente/stacktrace"
	"github.com/gin-contrib/requestid"
	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
	"strings"
)

const MaxSendCount = 10

// AllowedProviders is a set of valid provider names for discount coupons.
// While adding new providers, consider adding customized templates in email package.
var AllowedProviders = map[string]bool{
	"Kagi":       true,
	"Tuta":       true,
	"Notesnook":  true,
	"Windscribe": true,
	"Test":       true,
}

type Controller struct {
	Repo                  *discountcoupon.Repository
	UserRepo              *repo.UserRepository
	BillingController     *controller.BillingController
	EmailNotificationCtrl *email.EmailNotificationController
	DiscordController     *discord.DiscordController
}

type ClaimCouponRequest struct {
	ProviderName string `json:"providerName" binding:"required"`
	Email        string `json:"email" binding:"required"`
}

type AddCouponsRequest struct {
	ProviderName string   `json:"providerName" binding:"required"`
	Codes        []string `json:"codes" binding:"required"`
}

func (c *Controller) ClaimCoupon(ctx *gin.Context, req ClaimCouponRequest) error {
	if !AllowedProviders[req.ProviderName] {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("Invalid provider name"), "")
	}
	go c.processClaimRequest(ctx, req)
	return nil
}

func (c *Controller) processClaimRequest(ctx *gin.Context, req ClaimCouponRequest) {
	sanitizedEmail := emailUtil.NormalizeEmail(req.Email)
	logger :=
		log.WithField("provider", req.ProviderName).
			WithField("email", sanitizedEmail).
			WithField("req_id", requestid.Get(ctx))

	userID, err := c.UserRepo.GetUserIDWithEmailUnrestricted(sanitizedEmail)
	if err != nil {
		logger.WithError(err).Info("User not found for discount coupon claim")
		return
	}
	user, err := c.UserRepo.GetUserByIDInternal(userID)
	if err != nil {
		logger.WithError(err).Error("Failed to get user details")
		return
	}
	logger = logger.WithField("userID", userID)
	if user.FamilyAdminID != nil && *user.FamilyAdminID != user.ID {
		logger.Info("User is a family member, not eligible for discount coupon")
		return
	}

	err = c.BillingController.HasActiveSelfOrFamilySubscription(user.ID, true)
	if err != nil {
		logger.WithError(err).Error("User does not have active paid subscription")
		return
	}

	existingCoupon, err := c.Repo.GetClaimedCoupon(ctx, req.ProviderName, user.ID)
	if err != nil {
		logger.WithError(err).Error("Failed to get existing claimed coupon")
		return
	}

	if existingCoupon != nil {
		if existingCoupon.SentCount >= MaxSendCount {
			logger.Info("User has reached maximum send count for coupon")
			return
		}

		err = c.sendCouponEmail(ctx, user, existingCoupon.Code, req.ProviderName)
		if err != nil {
			logger.WithError(err).Error("Failed to resend coupon email")
			return
		}

		err = c.Repo.IncrementSentCount(ctx, req.ProviderName, existingCoupon.Code)
		if err != nil {
			logger.WithError(err).Error("Failed to increment sent count")
		}
		return
	}

	unclaimedCoupon, err := c.Repo.GetUnclaimedCoupon(ctx, req.ProviderName)
	if err != nil {
		logger.WithError(err).Error("Failed to get unclaimed coupon")
		return
	}

	if unclaimedCoupon == nil {
		c.alertCouponsDepletedDiscord(req.ProviderName)
		logger.Warn("No unclaimed coupons available")
		return
	}

	err = c.Repo.ClaimCoupon(ctx, req.ProviderName, unclaimedCoupon.Code, user.ID)
	if err != nil {
		logger.WithError(err).Error("Failed to claim coupon")
		return
	}

	err = c.sendCouponEmail(ctx, user, unclaimedCoupon.Code, req.ProviderName)
	if err != nil {
		logger.WithError(err).Error("Failed to send coupon email")
		return
	}

	logger.Info("Successfully claimed and sent coupon")
}

func (c *Controller) sendCouponEmail(ctx context.Context, user ente.User, couponCode, providerName string) error {
	templateData := map[string]interface{}{
		"CouponCode":   couponCode,
		"ProviderName": providerName,
	}

	var subject, templateName string
	switch providerName {
	case "Kagi":
		subject = "Ente Friends - Kagi trial code"
		templateName = "discount_coupon_kagi.html"
	case "Tuta":
		subject = "Ente Friends - Tuta discount code"
		templateName = "discount_coupon_tuta.html"
	case "Notesnook":
		subject = "Ente Friends - Notesnook discount code"
		templateName = "discount_coupon_notesnook.html"
	case "Windscribe":
		subject = "Ente Friends - Windscribe discount code"
		templateName = "discount_coupon_windscribe.html"
	case "Test":
		subject = "Ente Friends - Test trial code"
		templateName = "discount_coupon_test.html"
	default:
		subject = fmt.Sprintf("Your %s Discount Code", providerName)
		templateName = "discount_coupon.html"
	}
	return emailUtil.SendTemplatedEmailV2([]string{user.Email}, "Ente", "team@ente.com", subject, "base.html", templateName, templateData, nil)
}

func (c *Controller) alertCouponsDepletedDiscord(providerName string) {
	message := fmt.Sprintf("🚨 Alert: All discount coupons for provider **%s** have been claimed!", providerName)
	c.DiscordController.NotifyAdminAction(message)
}

func (c *Controller) AddCoupons(ctx *gin.Context, req AddCouponsRequest) error {
	if !AllowedProviders[req.ProviderName] {
		return ente.NewBadRequestWithMessage("Invalid provider name")
	}
	if len(req.Codes) == 0 {
		return ente.NewBadRequestWithMessage("No coupon codes provided")
	}

	// Filter out empty codes and validate
	validCodes := make([]string, 0, len(req.Codes))
	for _, code := range req.Codes {
		trimmed := strings.TrimSpace(code)
		if trimmed != "" {
			validCodes = append(validCodes, trimmed)
		}
	}
	if len(validCodes) == 0 {
		return nil
	}
	err := c.Repo.AddCoupons(ctx, req.ProviderName, req.Codes)
	if err != nil {
		return stacktrace.Propagate(err, "failed to add coupons")
	}

	return nil
}
