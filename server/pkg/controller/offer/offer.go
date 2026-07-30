package offer

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"slices"

	"github.com/ente/museum/pkg/controller/usercache"

	"github.com/ente/museum/ente"
	storageBonusEntity "github.com/ente/museum/ente/storagebonus"
	"github.com/ente/museum/pkg/controller/discord"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/storagebonus"
	"github.com/ente/museum/pkg/utils/billing"
	"github.com/ente/museum/pkg/utils/config"
	emailUtil "github.com/ente/museum/pkg/utils/email"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	log "github.com/sirupsen/logrus"
)

// OfferController controls all offer related operations
type OfferController struct {
	BlackFridayOffers ente.BlackFridayOfferPerCountry
	UserRepo          repo.UserRepository
	DiscordController *discord.DiscordController
	StorageBonusRepo  *storagebonus.Repository
	UserCacheCtrl     *usercache.Controller
}

func NewOfferController(
	userRepo repo.UserRepository,
	discordController *discord.DiscordController,
	storageBonusRepo *storagebonus.Repository,
	userCacheCtrl *usercache.Controller,
) *OfferController {
	blackFridayOffers := make(ente.BlackFridayOfferPerCountry)
	path, err := config.BillingConfigFilePath("black-friday.json")
	if err != nil {
		log.Fatalf("Skipping BF configuration, config file not found: %v", err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		log.Info("Skipping optional Black Friday offers", err)
	}
	err = json.Unmarshal(data, &blackFridayOffers)
	if err != nil {
		log.Info("Could not get Black Friday Offer", err)
	}
	return &OfferController{
		BlackFridayOffers: blackFridayOffers,
		UserRepo:          userRepo,
		DiscordController: discordController,
		StorageBonusRepo:  storageBonusRepo,
		UserCacheCtrl:     userCacheCtrl,
	}
}

func (c *OfferController) GetBlackFridayOffers(countryCode string) []ente.BlackFridayOffer {
	if slices.Contains(billing.CountriesInEU, countryCode) {
		countryCode = "EU"
	}

	if offers, found := c.BlackFridayOffers[countryCode]; found {
		return offers
	}
	// unable to find plans for given country code, return plans for default country
	defaultCountry := billing.GetDefaultPlanCountry()
	return c.BlackFridayOffers[defaultCountry]
}

func (c *OfferController) ApplyOffer(email string, productID string) error {
	var offerToBeApplied ente.BlackFridayOffer
	found := false
	for _, offers := range c.BlackFridayOffers {
		for _, offer := range offers {
			if offer.ID == productID {
				found = true
				offerToBeApplied = offer
			}
		}
	}
	if !found {
		return stacktrace.Propagate(ente.ErrNotFound, "Could not find an offer for  %s", productID)
	}
	var validTill int64
	if offerToBeApplied.PeriodInYears == ente.Period3Years {
		validTill = time.NDaysFromNow(3 * 365)
	} else if offerToBeApplied.PeriodInYears == ente.Period5Years {
		validTill = time.NDaysFromNow(5 * 365)
	} else if offerToBeApplied.PeriodInYears == ente.Period10Years {
		validTill = time.NDaysFromNow(10 * 365)
	} else {
		return stacktrace.Propagate(ente.ErrNotFound, "Could not find a valid time period for  %s", productID)
	}

	userID, err := c.UserRepo.GetUserIDWithEmailUnrestricted(email)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			log.Error("Product purchased with unknown email: " + email)
			c.DiscordController.Notify("Unknown user paid " + offerToBeApplied.Price)
			return nil
		} else {
			return stacktrace.Propagate(err, "")
		}
	}

	err = c.StorageBonusRepo.InsertAddOnBonus(context.Background(), storageBonusEntity.AddOnBf2024, userID, validTill, offerToBeApplied.Storage)
	if err != nil {
		c.DiscordController.Notify("Error inserting bonus")
		return stacktrace.Propagate(err, "")
	}
	go c.UserCacheCtrl.GetActiveStorageBonus(context.Background(), userID)
	go emailUtil.SendTemplatedEmail([]string{email}, "Ente", "team@ente.com",
		ente.BF2024EmailSubject,
		ente.BF2024EmailTemplate, map[string]interface{}{
			"Storage": c.readableStorage(offerToBeApplied.Storage),
		}, nil)
	c.DiscordController.NotifyBlackFridayUser(userID, offerToBeApplied.Price)
	return nil
}

func (c *OfferController) readableStorage(storage int64) string {
	return fmt.Sprintf("%d GB", storage/(1<<30))
}
