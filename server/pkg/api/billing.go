package api

import (
	b64 "encoding/base64"
	"encoding/json"
	"fmt"
	"io"

	"net/http"

	"github.com/ente/museum/pkg/utils/billing"
	"github.com/ente/museum/pkg/utils/network"
	"github.com/gin-contrib/requestid"

	"github.com/ente/stacktrace"
	log "github.com/sirupsen/logrus"

	"github.com/awa/go-iap/appstore"
	"github.com/awa/go-iap/playstore"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/gin-gonic/gin"
)

// BillingHandler exposes request handlers for all billing related requests
type BillingHandler struct {
	Controller          *controller.BillingController
	AppStoreController  *controller.AppStoreController
	PlayStoreController *controller.PlayStoreController
	StripeController    *controller.StripeController
}

// GetPlansV2 returns the available default Stripe account subscription plans for the country the client request came from the
func (h *BillingHandler) GetPlansV2(c *gin.Context) {
	plans := h.Controller.GetPlansV2(network.GetClientCountry(c), ente.DefaultStripeAccountCountry)
	freePlan := billing.GetFreePlan()

	log.Info(log.Fields{
		"req_id":   requestid.Get(c),
		"plans":    fmt.Sprintf("%+v", plans),
		"freePlan": fmt.Sprintf("%+v", freePlan),
	})

	c.JSON(http.StatusOK, gin.H{
		"plans":    plans,
		"freePlan": freePlan,
	})
}

// GetUserPlans returns the available  plans from the stripe account and the country the user's existing plan is from
func (h *BillingHandler) GetUserPlans(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	plans, err := h.Controller.GetUserPlans(c, userID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Failed to user plans"))
		return
	}
	freePlan := billing.GetFreePlan()

	log.Info(log.Fields{
		"user_id":  userID,
		"req_id":   requestid.Get(c),
		"plans":    fmt.Sprintf("%+v", plans),
		"freePlan": fmt.Sprintf("%+v", freePlan),
	})

	c.JSON(http.StatusOK, gin.H{
		"plans":    plans,
		"freePlan": freePlan,
	})
}

// GetStripeAccountCountry returns the stripe account country the user's existing plan is from
// if he doesn't have default stripe account country is returned
func (h *BillingHandler) GetStripeAccountCountry(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	stripeAccountCountry, err := h.Controller.GetStripeAccountCountry(userID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, "Failed to get stripe account country"))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"stripeAccountCountry": stripeAccountCountry,
	})
}

// Deprecated:
// GetUsage returns the storage usage for the requesting user
func (h *BillingHandler) GetUsage(c *gin.Context) {
	//	 status code to indicate that endpoint is deprecated
	c.JSON(http.StatusGone, gin.H{
		"message": "This endpoint is deprecated.",
	})
}

// GetSubscription returns the current subscription for a user if any
func (h *BillingHandler) GetSubscription(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	subscription, err := h.Controller.GetSubscription(c, userID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"subscription": subscription,
	})
}

// VerifySubscription verifies and returns the verified subscription
func (h *BillingHandler) VerifySubscription(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	var request ente.SubscriptionVerificationRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	subscription, err := h.Controller.VerifySubscription(userID,
		request.PaymentProvider, request.ProductID, request.VerificationData)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"subscription": subscription,
	})
}

// AndroidNotificationHandler handles the notifications from PlayStore
func (h *BillingHandler) AndroidNotificationHandler(c *gin.Context) {
	var request ente.AndroidNotification
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	decoded, err := b64.StdEncoding.DecodeString(request.Message.Data)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	log.Println("Received notification " + string(decoded))
	var notification playstore.DeveloperNotification
	err = json.Unmarshal(decoded, &notification)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	if notification.TestNotification.Version == "1.0" {
		log.Info("Ignoring test notification")
	} else {
		err = h.PlayStoreController.HandleNotification(notification)
		if err != nil {
			handler.Error(c, stacktrace.Propagate(err, ""))
			return
		}
	}
	c.JSON(http.StatusOK, gin.H{})
}

// IOSNotificationHandler handles the notifications from AppStore
func (h *BillingHandler) IOSNotificationHandler(c *gin.Context) {
	var notification appstore.SubscriptionNotification
	if err := handler.BindJSON(c, &notification); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}

	err := h.AppStoreController.HandleNotification(c, notification)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}

	c.JSON(http.StatusOK, gin.H{})
}

// GetCheckoutSession generates and returns stripe checkout session for subscription purchase
func (h *BillingHandler) GetCheckoutSession(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	productID := c.Query("productID")
	redirectRootURL, err := h.Controller.GetRedirectURL(c)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	sessionID, err := h.StripeController.GetCheckoutSession(productID, userID, redirectRootURL)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{"sessionID": sessionID})
}

// StripeINNotificationHandler handles the notifications from older StripeIN account
func (h *BillingHandler) StripeINNotificationHandler(c *gin.Context) {
	notification, err := io.ReadAll(c.Request.Body)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	stripeSignature := c.GetHeader(ente.StripeSignature)
	err = h.StripeController.HandleINNotification(notification, stripeSignature)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}

	c.JSON(http.StatusOK, gin.H{})
}

// StripeUSNotificationHandler handles the notifications from new StripeUS account
func (h *BillingHandler) StripeUSNotificationHandler(c *gin.Context) {
	notification, err := io.ReadAll(c.Request.Body)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	stripeSignature := c.GetHeader(ente.StripeSignature)
	err = h.StripeController.HandleUSNotification(notification, stripeSignature)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}

	c.JSON(http.StatusOK, gin.H{})
}

// StripeUpdateSubscription handles stripe subscription updates requests
func (h *BillingHandler) StripeUpdateSubscription(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	var request ente.StripeUpdateRequest
	if err := handler.BindJSON(c, &request); err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	s, err := h.StripeController.UpdateSubscription(request.ProductID, userID)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{"result": s})
}

// StripeCancelSubscription handles stripe subscription cancel requests
func (h *BillingHandler) StripeCancelSubscription(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	subscription, err := h.StripeController.UpdateSubscriptionCancellationStatus(userID, true)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{"subscription": subscription})
}

// StripeActivateSubscription handles stripe subscription activation requests
func (h *BillingHandler) StripeActivateSubscription(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	subscription, err := h.StripeController.UpdateSubscriptionCancellationStatus(userID, false)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{"subscription": subscription})
}

// GetStripeCustomerPortal handles stripe customer portal url retrieval request
func (h *BillingHandler) GetStripeCustomerPortal(c *gin.Context) {
	userID := auth.GetUserID(c.Request.Header)
	redirectRootURL, err := h.Controller.GetRedirectURL(c)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	url, err := h.StripeController.GetStripeCustomerPortal(userID, redirectRootURL)
	if err != nil {
		handler.Error(c, stacktrace.Propagate(err, ""))
		return
	}
	c.JSON(http.StatusOK, gin.H{"url": url})
}
