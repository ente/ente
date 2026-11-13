package controller

import (
	"errors"
	"fmt"
	"strconv"

	"github.com/ente/museum/pkg/controller/discord"
	"github.com/ente/museum/pkg/external/listmonk"
	"github.com/ente/stacktrace"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/viper"
)

type MailingListsController struct {
	listmonkListIDs     []int
	listmonkCredentials listmonk.Credentials
	discordController   *discord.DiscordController
}

func NewMailingListsController(discordController *discord.DiscordController) *MailingListsController {
	listmonkCredentials := listmonk.Credentials{
		BaseURL:  viper.GetString("listmonk.server-url"),
		Username: viper.GetString("listmonk.username"),
		Password: viper.GetString("listmonk.password"),
	}

	listmonkListIDs := viper.GetIntSlice("listmonk.list-ids")

	return &MailingListsController{
		listmonkCredentials: listmonkCredentials,
		listmonkListIDs:     listmonkListIDs,
		discordController:   discordController,
	}
}

func (c *MailingListsController) Subscribe(email string) error {
	if !(c.shouldSkipListmonk()) {
		err := c.listmonkSubscribe(email)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
	}
	return nil
}

func (c *MailingListsController) Unsubscribe(email string) error {
	if !(c.shouldSkipListmonk()) {
		err := c.listmonkUnsubscribe(email)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
	}
	return nil
}

func (c *MailingListsController) shouldSkipListmonk() bool {
	if c.listmonkCredentials.BaseURL == "" || c.listmonkCredentials.Username == "" ||
		c.listmonkCredentials.Password == "" || len(c.listmonkListIDs) == 0 {
		return true
	}
	return false
}

func (c *MailingListsController) listmonkSubscribe(email string) error {
	data := map[string]interface{}{
		"email": email,
		"lists": c.listmonkListIDs,
	}
	err := listmonk.SendRequest("POST", c.listmonkCredentials.BaseURL+"/api/subscribers", data,
		c.listmonkCredentials.Username, c.listmonkCredentials.Password)
	if err != nil {
		log.Errorf("Listmonk subscribe failed '%s': %s", email, err)
		c.notifyListmonkFailure("Listmonk subscribe failed", err)
	}
	return err
}

func (c *MailingListsController) listmonkUnsubscribe(email string) error {
	// Listmonk deletion needs a subscriber ID, so look it up by email first.
	id, err := listmonk.GetSubscriberID(c.listmonkCredentials.BaseURL+"/api/subscribers",
		c.listmonkCredentials.Username, c.listmonkCredentials.Password, email)
	if err != nil {
		log.Errorf("Listmonk - Unsub failed for '%s': %s", email, err)
		if !errors.Is(err, listmonk.ErrSubscriberNotFound) {
			c.notifyListmonkFailure("Listmonk - Unsub failed", err)
		}
		return stacktrace.Propagate(err, "")
	}

	err = listmonk.SendRequest("DELETE", c.listmonkCredentials.BaseURL+"/api/subscribers/"+strconv.Itoa(id),
		map[string]interface{}{}, c.listmonkCredentials.Username, c.listmonkCredentials.Password)
	if err != nil {
		log.Errorf("Listmonk - Unsub failed to delete '%s': %s", email, err)
		c.notifyListmonkFailure("Listmonk - Unsub failed to delete", err)
	}
	return err
}

func (c *MailingListsController) notifyListmonkFailure(message string, err error) {
	c.discordController.Notify(fmt.Sprintf("%s: %v", message, err))
}
