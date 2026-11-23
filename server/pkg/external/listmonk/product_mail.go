package listmonk

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"strings"

	"github.com/google/uuid"
	"github.com/lib/pq"
)

type ProductMailer struct {
	Credentials
	ListID                  int
	TemplateID              int
	UnsubscribeCampaignUUID string
}

func (m ProductMailer) Configured() bool {
	_, err := uuid.Parse(m.UnsubscribeCampaignUUID)
	return err == nil && m.ListID > 0 && m.TemplateID > 0 &&
		m.BaseURL != "" && m.Username != "" && m.Password != ""
}

func (m ProductMailer) Send(emails []string, subject string, body string) error {
	baseURL := strings.TrimRight(m.BaseURL, "/")
	var sendErrors error
	for addresses := range slices.Chunk(emails, 8) {
		recipients, err := m.productSubscribers(baseURL, addresses)
		if err != nil {
			sendErrors = errors.Join(sendErrors, err)
			continue
		}
		for _, subscriber := range recipients {
			if _, err := uuid.Parse(subscriber.UUID); err != nil {
				sendErrors = errors.Join(sendErrors, fmt.Errorf("invalid listmonk subscriber UUID: %w", err))
				continue
			}
			unsubscribeURL := baseURL + "/subscription/" + m.UnsubscribeCampaignUUID + "/" + subscriber.UUID
			request := map[string]any{
				"subscriber_email": subscriber.Email,
				"template_id":      m.TemplateID,
				"subject":          subject,
				"content_type":     "html",
				"data": map[string]string{
					"Body":           body,
					"UnsubscribeURL": unsubscribeURL,
				},
				"headers": []map[string]string{
					{"List-Unsubscribe": "<" + unsubscribeURL + ">"},
					{"List-Unsubscribe-Post": "List-Unsubscribe=One-Click"},
				},
			}
			if err := SendRequest(http.MethodPost, baseURL+"/api/tx", request, m.Username, m.Password); err != nil {
				sendErrors = errors.Join(sendErrors, err)
			}
		}
	}
	return sendErrors
}

type productSubscriber struct {
	Email string `json:"email"`
	UUID  string `json:"uuid"`
}

func (m ProductMailer) productSubscribers(baseURL string, addresses []string) ([]productSubscriber, error) {
	quotedEmails := make([]string, len(addresses))
	for i, address := range addresses {
		quotedEmails[i] = pq.QuoteLiteral(strings.ToLower(strings.TrimSpace(address)))
	}
	listID := strconv.Itoa(m.ListID)
	query := "subscriber_lists.list_id = " + listID +
		" AND subscribers.status = 'enabled'" +
		" AND subscriber_lists.status <> 'unsubscribed'" +
		" AND (subscriber_lists.status = 'confirmed' OR EXISTS (SELECT 1 FROM lists" +
		" WHERE lists.id = subscriber_lists.list_id AND lists.optin = 'single'))" +
		" AND subscribers.email IN (" + strings.Join(quotedEmails, ",") + ")"
	params := url.Values{"list_id": {listID}, "query": {query}, "per_page": {"all"}}
	req, err := http.NewRequest(http.MethodGet, baseURL+"/api/subscribers?"+params.Encode(), nil)
	if err != nil {
		return nil, err
	}
	req.SetBasicAuth(m.Username, m.Password)
	client := &http.Client{Timeout: listmonkRequestTimeout}
	resp, err := client.Do(req)
	if err != nil {
		if requestErr, ok := err.(*url.Error); ok {
			err = requestErr.Err
		}
		return nil, fmt.Errorf("look up product subscribers in listmonk: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("look up product subscribers in listmonk: %s", resp.Status)
	}
	var result struct {
		Data struct {
			Results []productSubscriber `json:"results"`
		} `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode listmonk product subscribers: %w", err)
	}
	return result.Data.Results, nil
}
