package controller

import (
	"errors"
	"fmt"
	"net/url"
	"strconv"
	"strings"

	"github.com/ente/museum/pkg/controller/discord"
	"github.com/ente/museum/pkg/external/listmonk"
	"github.com/ente/museum/pkg/external/zoho"
	"github.com/ente/stacktrace"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/viper"
)

// MailingListsController is used to keeping the external mailing lists in sync
// with customer email changes.
//
// MailingListsController contains methods for keeping external mailing lists in
// sync when new users sign up, or update their email, or delete their account.
// Currently, these mailing lists are hosted on Zoho Campaigns.
//
// See also: Syncing emails with Zoho Campaigns
type MailingListsController struct {
	zohoAccessToken     string
	zohoListKey         string
	zohoTopicIds        string
	zohoCredentials     zoho.Credentials
	listmonkListIDs     []int
	listmonkCredentials listmonk.Credentials
	discordController   *discord.DiscordController
}

// Return a new instance of MailingListsController
func NewMailingListsController(discordController *discord.DiscordController) *MailingListsController {
	zohoCredentials := zoho.Credentials{
		ClientID:     viper.GetString("zoho.client-id"),
		ClientSecret: viper.GetString("zoho.client-secret"),
		RefreshToken: viper.GetString("zoho.refresh-token"),
	}

	// The Zoho "List Key" identifies a particular list of email IDs that are
	// stored in Zoho. All the actions that we perform (adding, removing and
	// updating emails) are done on this list.
	//
	// https://www.zoho.com/campaigns/help/developers/list-management.html
	zohoListKey := viper.GetString("zoho.list-key")

	// List of topics to which emails are sent.
	//
	// Ostensibly, we can get them from their API
	// https://www.zoho.com/campaigns/oldhelp/api/get-topics.html
	//
	// But that doesn't currently work, luckily we can get these IDs by looking
	// at the HTML source of the topic update dashboard page.
	zohoTopicIds := viper.GetString("zoho.topic-ids")

	// Zoho has a rate limit on the number of access tokens that can created
	// within a given time period. So as an aid in debugging, allow the access
	// token to be passed in. This will not be present in production - there
	// we'll use the refresh token to create an access token on demand.
	zohoAccessToken := viper.GetString("zoho.access_token")

	listmonkCredentials := listmonk.Credentials{
		BaseURL:  viper.GetString("listmonk.server-url"),
		Username: viper.GetString("listmonk.username"),
		Password: viper.GetString("listmonk.password"),
	}

	// An array of integer values indicating the id of listmonk campaign
	// mailing list to which the subscriber needs to added
	listmonkListIDs := viper.GetIntSlice("listmonk.list-ids")

	return &MailingListsController{
		zohoCredentials:     zohoCredentials,
		zohoListKey:         zohoListKey,
		zohoTopicIds:        zohoTopicIds,
		zohoAccessToken:     zohoAccessToken,
		listmonkCredentials: listmonkCredentials,
		listmonkListIDs:     listmonkListIDs,
		discordController:   discordController,
	}
}

// Add the given email address to our default Zoho Campaigns list
// or Listmonk Campaigns List
//
// It is valid to resubscribe an email that has previously been unsubscribe.
//
// # Syncing emails with Zoho Campaigns
//
// Zoho Campaigns does not support maintaining a list of raw email addresses
// that can be later updated or deleted via their API. So instead, we maintain
// the email addresses of our customers in a Zoho Campaign "list", and subscribe
// or unsubscribe them to this list.
func (c *MailingListsController) Subscribe(email string) error {
	if !(c.shouldSkipZoho()) {
		// Need to set "Signup Form Disabled" in the list settings since we use this
		// list to keep track of emails that have already been verified.
		//
		// > You can use this API to add contacts to your mailing lists. For signup
		//   form enabled mailing lists, the contacts will receive a confirmation
		//   email. For signup form disabled lists, contacts will be added without
		//   any confirmations.
		//
		// https://www.zoho.com/campaigns/help/developers/contact-subscribe.html
		err := c.doListActionZoho("listsubscribe", email)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
	}
	if !(c.shouldSkipListmonk()) {
		err := c.listmonkSubscribe(email)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
	}
	return nil
}

// Unsubscribe the given email address to our default Zoho Campaigns list
// or Listmonk Campaigns List
//
// See: [Note: Syncing emails with Zoho Campaigns]
func (c *MailingListsController) Unsubscribe(email string) error {
	if !(c.shouldSkipZoho()) {
		// https://www.zoho.com/campaigns/help/developers/contact-unsubscribe.html
		err := c.doListActionZoho("listunsubscribe", email)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
	}
	if !(c.shouldSkipListmonk()) {
		err := c.listmonkUnsubscribe(email)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
	}
	return nil
}

// shouldSkipZoho() checks if the MailingListsController
// should be skipped due to missing credentials.
func (c *MailingListsController) shouldSkipZoho() bool {
	return c.zohoCredentials.RefreshToken == ""
}

// shouldSkipListmonk() checks if the Listmonk mailing list
// should be skipped due to missing credentials
// listmonklistIDs value.
//
// ListmonkListIDs is an optional field for subscribing an email address
// (user gets added to the default list),
// but is a required field for unsubscribing an email address
func (c *MailingListsController) shouldSkipListmonk() bool {
	if c.listmonkCredentials.BaseURL == "" || c.listmonkCredentials.Username == "" ||
		c.listmonkCredentials.Password == "" || len(c.listmonkListIDs) == 0 {
		// Skip
		return true
	}
	return false
}

// Both the listsubscribe and listunsubscribe Zoho Campaigns API endpoints work
// similarly, so use this function to keep the common code.
func (c *MailingListsController) doListActionZoho(action string, email string) error {
	// Query escape the email so that any pluses get converted to %2B.
	escapedEmail := url.QueryEscape(email)
	contactInfo := fmt.Sprintf("{Contact+Email: \"%s\"}", escapedEmail)
	// Instead of using QueryEscape, use PathEscape. QueryEscape escapes the "+"
	// character, which causes Zoho API to not recognize the parameter.
	escapedContactInfo := url.PathEscape(contactInfo)

	url := fmt.Sprintf(
		"https://campaigns.zoho.com/api/v1.1/json/%s?resfmt=JSON&listkey=%s&contactinfo=%s&topic_id=%s",
		action, c.zohoListKey, escapedContactInfo, c.zohoTopicIds)

	zohoAccessToken, err := zoho.DoRequest("POST", url, c.zohoAccessToken, c.zohoCredentials)
	c.zohoAccessToken = zohoAccessToken

	if err != nil {
		// This is not necessarily an error, and can happen when the customer
		// had earlier unsubscribed from our organization emails in Zoho,
		// selecting the "Erase my data" option. This causes Zoho to remove the
		// customer's entire record from their database.
		//
		// Then later, say if the customer deletes their account from ente, we
		// would try to unsubscribe their email but it wouldn't be present in
		// Zoho, and this API call would've failed.
		//
		// In such a case, Zoho will return the following response:
		//
		//   { code":"2103",
		//     "message":"Contact does not exist.",
		//     "version":"1.1",
		//     "uri":"/api/v1.1/json/listunsubscribe",
		//     "status":"error"}
		//
		// Special case these to reduce the severity level so as to not cause
		// error log spam.
		if strings.Contains(err.Error(), "Contact does not exist") {
			log.Warnf("Zoho - Could not %s '%s': %s", action, email, err)
		} else {
			log.Errorf("Zoho - Could not %s '%s': %s", action, email, err)
		}
	}

	return stacktrace.Propagate(err, "")
}

// Subscribes an email address to a particular listmonk campaign mailing list
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

// Unsubscribes an email address to a particular listmonk campaign mailing list
func (c *MailingListsController) listmonkUnsubscribe(email string) error {
	// Listmonk doesn't provide an endpoint for unsubscribing users
	// from a particular list directly via their email
	//
	// Thus, fetching subscriberID through email address,
	// and then calling the endpoint to delete that user
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
