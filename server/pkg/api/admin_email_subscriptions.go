package api

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"sync/atomic"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/external/listmonk"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/crypto"
	emailUtil "github.com/ente/museum/pkg/utils/email"
	"github.com/ente/museum/pkg/utils/handler"
	"github.com/gin-contrib/requestid"
	"github.com/gin-gonic/gin"
	"github.com/sirupsen/logrus"
	"github.com/spf13/viper"
)

var emailSubscriptionBackfillInFlight atomic.Bool

func (h *AdminHandler) BackfillEmailSubscriptionsFromListmonk(c *gin.Context) {
	var req struct {
		NewsletterListID int       `json:"newsletterListID" binding:"required,gt=0"`
		CreatedBefore    time.Time `json:"createdBefore" binding:"required"`
		Apply            bool      `json:"apply"`
	}
	if err := handler.BindJSON(c, &req); err != nil {
		handler.Error(c, err)
		return
	}
	if req.CreatedBefore.IsZero() || req.CreatedBefore.After(time.Now()) {
		handler.Error(c, ente.NewBadRequestWithMessage("createdBefore must be the signup enrollment cutoff in RFC3339 format"))
		return
	}
	credentials := listmonk.Credentials{
		BaseURL:  strings.TrimRight(viper.GetString("listmonk.server-url"), "/"),
		Username: viper.GetString("listmonk.username"),
		Password: viper.GetString("listmonk.password"),
	}
	if credentials.BaseURL == "" || credentials.Username == "" || credentials.Password == "" {
		handler.Error(c, ente.NewBadRequestWithMessage("listmonk is not configured"))
		return
	}
	if !emailSubscriptionBackfillInFlight.CompareAndSwap(false, true) {
		c.JSON(http.StatusConflict, gin.H{"error": "email subscription backfill already running on this host"})
		return
	}
	reqID := requestid.Get(c)
	logger := logrus.WithFields(logrus.Fields{
		"req_id":          reqID,
		"admin_id":        auth.GetUserID(c.Request.Header),
		"newsletter_list": req.NewsletterListID,
		"created_before":  req.CreatedBefore,
		"apply":           req.Apply,
	})
	go func() {
		defer emailSubscriptionBackfillInFlight.Store(false)
		counts, err := h.backfillEmailSubscriptions(context.Background(), credentials,
			req.NewsletterListID, req.CreatedBefore.UnixMicro(), req.Apply)
		logger := logger.WithFields(logrus.Fields{
			"scanned":           counts.Scanned,
			"matched":           counts.Matched,
			"unmatched":         counts.Unmatched,
			"after_cutoff":      counts.AfterCutoff,
			"existing":          counts.Existing,
			"opt_out_conflicts": counts.OptOutConflicts,
			"subscribed":        counts.Subscribed,
			"suppressed":        counts.Suppressed,
		})
		status := "completed"
		if err != nil {
			status = "failed"
			logger.WithError(err).Error("Listmonk email subscription backfill failed")
		} else {
			logger.Info("Listmonk email subscription backfill completed")
		}
		if h.DiscordController != nil {
			mode := "dry run"
			if req.Apply {
				mode = "apply"
			}
			h.DiscordController.Notify(fmt.Sprintf(
				"Product Mails backfill (%s) %s on `%s`. Request `%s`. Newsletter list %d. Scanned %d, matched %d, unmatched %d, after cutoff %d, existing %d, opt-out conflicts %d, subscribed %d, suppressed %d.",
				mode, status, h.DiscordController.HostName, reqID, req.NewsletterListID,
				counts.Scanned, counts.Matched, counts.Unmatched, counts.AfterCutoff, counts.Existing,
				counts.OptOutConflicts, counts.Subscribed, counts.Suppressed,
			))
		}
	}()
	c.JSON(http.StatusAccepted, gin.H{"requestID": reqID, "apply": req.Apply})
}

type emailSubscriptionBackfillCounts struct {
	repo.EmailSubscriptionBackfillCounts
	Scanned int
}

func (h *AdminHandler) backfillEmailSubscriptions(ctx context.Context, credentials listmonk.Credentials,
	newsletterListID int, createdBefore int64, apply bool) (emailSubscriptionBackfillCounts, error) {
	const pageSize = 1000
	var total emailSubscriptionBackfillCounts
	endpoint := credentials.BaseURL + "/api/subscribers?order=ASC"
	for pageNumber := 1; ; pageNumber++ {
		page, err := listmonk.ListSubscribers(endpoint, credentials.Username, credentials.Password, pageNumber, pageSize)
		if err != nil {
			return total, fmt.Errorf("fetch listmonk subscribers page %d: %w", pageNumber, err)
		}
		preferences := make(map[string]bool, len(page.Results))
		for _, subscriber := range page.Results {
			subscribed, known := productMailPreference(subscriber, newsletterListID)
			email := emailUtil.NormalizeEmail(subscriber.Email)
			if !known || email == "" {
				continue
			}
			hash, err := crypto.GetHash(email, h.HashingKey)
			if err != nil {
				return total, fmt.Errorf("hash listmonk subscriber email: %w", err)
			}
			if current, exists := preferences[hash]; !exists || current {
				preferences[hash] = subscribed
			}
		}
		counts, err := h.EmailSubscriptionRepo.BackfillProductMails(ctx, preferences, createdBefore, apply)
		if err != nil {
			return total, fmt.Errorf("backfill subscribers page %d: %w", pageNumber, err)
		}
		total.Scanned += len(page.Results)
		total.Matched += counts.Matched
		total.Unmatched += counts.Unmatched
		total.AfterCutoff += counts.AfterCutoff
		total.Existing += counts.Existing
		total.OptOutConflicts += counts.OptOutConflicts
		total.Subscribed += counts.Subscribed
		total.Suppressed += counts.Suppressed
		if len(page.Results) == 0 || total.Scanned >= page.Total {
			return total, nil
		}
	}
}

func productMailPreference(subscriber listmonk.Subscriber, newsletterListID int) (subscribed, known bool) {
	if subscriber.Status == "blocklisted" {
		return false, true
	}
	for _, list := range subscriber.Lists {
		if list.ID != newsletterListID {
			continue
		}
		if list.Status == "unsubscribed" {
			return false, true
		}
		if subscriber.Status == "enabled" &&
			(list.Status == "confirmed" || list.Status == "unconfirmed" && list.OptIn == "single") {
			return true, true
		}
	}
	return false, false
}
