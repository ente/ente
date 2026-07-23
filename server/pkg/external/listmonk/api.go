package listmonk

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/ente/stacktrace"
)

// Listmonk credentials to interact with the Listmonk API.
// It specifies BaseURL (url of the running listmonk server,
// Listmonk Username and Password.
// Visit https://listmonk.app/ to learn more about running
// Listmonk locally
type Credentials struct {
	BaseURL  string
	Username string
	Password string
}

const listmonkRequestTimeout = 60 * time.Second

var ErrSubscriberNotFound = errors.New("subscriber not found")

// Subscriber captures a listmonk subscriber record required by museum.
type Subscriber struct {
	Email   string
	ListIDs []int
}

// SubscribersPage represents one paginated subscribers page from listmonk.
type SubscribersPage struct {
	Results []Subscriber
	Total   int
	Page    int
	PerPage int
}

// GetSubscriberID returns subscriber id of the provided email address,
// else returns an error if email was not found
func GetSubscriberID(endpoint string, username string, password string, subscriberEmail string) (int, error) {
	// Struct for the received API response.
	// Can define other fields as well that can be
	// extracted from response JSON
	type SubscriberResponse struct {
		Data struct {
			Results []struct {
				ID int `json:"id"`
			} `json:"results"`
		} `json:"data"`
	}

	// Constructing query parameters
	// Escape single quotes to prevent SQL-like injection in Listmonk's query syntax
	sanitizedEmail := strings.ReplaceAll(subscriberEmail, "'", "''")
	queryParams := url.Values{}
	queryParams.Set("query", fmt.Sprintf("subscribers.email = '%s'", sanitizedEmail))

	// Constructing the URL with query parameters
	endpointURL, err := url.Parse(endpoint)
	if err != nil {
		return 0, stacktrace.Propagate(err, "")
	}
	endpointURL.RawQuery = queryParams.Encode()

	req, err := http.NewRequest("GET", endpointURL.String(), nil)
	if err != nil {
		return 0, stacktrace.Propagate(err, "")
	}

	req.SetBasicAuth(username, password)

	// Sending the HTTP request
	client := &http.Client{Timeout: listmonkRequestTimeout}
	resp, err := client.Do(req)
	if err != nil {
		return 0, stacktrace.Propagate(err, "")
	}
	defer resp.Body.Close()

	// Reading the response body
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return 0, stacktrace.Propagate(err, "")
	}
	if resp.StatusCode != http.StatusOK {
		return 0, stacktrace.Propagate(
			fmt.Errorf("listmonk request failed with status %d: %s", resp.StatusCode, strings.TrimSpace(string(body))),
			"",
		)
	}

	// Parsing the JSON response
	var subscriberResp SubscriberResponse
	if err := json.Unmarshal(body, &subscriberResp); err != nil {
		return 0, stacktrace.Propagate(err, "")
	}

	// Checking if there are any subscribers found
	if len(subscriberResp.Data.Results) == 0 {
		return 0, stacktrace.Propagate(ErrSubscriberNotFound, "")
	}

	// Extracting the ID from the response
	id := subscriberResp.Data.Results[0].ID

	return id, nil
}

// ListSubscribers returns one paginated subscribers page from listmonk.
func ListSubscribers(endpoint string, username string, password string, page int, perPage int) (SubscribersPage, error) {
	type subscriberResponse struct {
		Data struct {
			Results []map[string]json.RawMessage `json:"results"`
			Total   int                          `json:"total"`
			Page    int                          `json:"page"`
			PerPage int                          `json:"per_page"`
		} `json:"data"`
	}

	endpointURL, err := url.Parse(endpoint)
	if err != nil {
		return SubscribersPage{}, stacktrace.Propagate(err, "")
	}

	queryParams := endpointURL.Query()
	queryParams.Set("page", strconv.Itoa(page))
	queryParams.Set("per_page", strconv.Itoa(perPage))
	endpointURL.RawQuery = queryParams.Encode()

	req, err := http.NewRequest("GET", endpointURL.String(), nil)
	if err != nil {
		return SubscribersPage{}, stacktrace.Propagate(err, "")
	}
	req.SetBasicAuth(username, password)

	client := &http.Client{Timeout: listmonkRequestTimeout}
	resp, err := client.Do(req)
	if err != nil {
		return SubscribersPage{}, stacktrace.Propagate(err, "")
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return SubscribersPage{}, stacktrace.Propagate(err, "")
	}
	if resp.StatusCode != http.StatusOK {
		return SubscribersPage{}, stacktrace.Propagate(
			fmt.Errorf("listmonk request failed with status %d: %s", resp.StatusCode, strings.TrimSpace(string(body))),
			"",
		)
	}

	var parsed subscriberResponse
	if err := json.Unmarshal(body, &parsed); err != nil {
		return SubscribersPage{}, stacktrace.Propagate(err, "")
	}

	results := make([]Subscriber, 0, len(parsed.Data.Results))
	for _, row := range parsed.Data.Results {
		subscriber, parseErr := parseSubscriber(row)
		if parseErr != nil {
			return SubscribersPage{}, stacktrace.Propagate(parseErr, "")
		}
		results = append(results, subscriber)
	}

	return SubscribersPage{
		Results: results,
		Total:   parsed.Data.Total,
		Page:    parsed.Data.Page,
		PerPage: parsed.Data.PerPage,
	}, nil
}

func parseSubscriber(data map[string]json.RawMessage) (Subscriber, error) {
	emailRaw, ok := data["email"]
	if !ok {
		return Subscriber{}, stacktrace.Propagate(errors.New("missing email in listmonk subscriber payload"), "")
	}
	var email string
	if err := json.Unmarshal(emailRaw, &email); err != nil {
		return Subscriber{}, stacktrace.Propagate(err, "failed to parse listmonk subscriber email")
	}

	var listIDs []int
	if listsRaw, ok := data["lists"]; ok {
		ids, err := decodeListIDs(listsRaw)
		if err != nil {
			return Subscriber{}, stacktrace.Propagate(err, "failed to parse listmonk subscriber lists")
		}
		listIDs = ids
	} else if listIDsRaw, ok := data["list_ids"]; ok {
		ids, err := decodeListIDs(listIDsRaw)
		if err != nil {
			return Subscriber{}, stacktrace.Propagate(err, "failed to parse listmonk subscriber list_ids")
		}
		listIDs = ids
	}

	return Subscriber{
		Email:   email,
		ListIDs: listIDs,
	}, nil
}

func decodeListIDs(raw json.RawMessage) ([]int, error) {
	type listWithID struct {
		ID int `json:"id"`
	}

	if len(raw) == 0 || string(raw) == "null" {
		return []int{}, nil
	}

	var directIntIDs []int
	if err := json.Unmarshal(raw, &directIntIDs); err == nil {
		return directIntIDs, nil
	}

	var objectIDs []listWithID
	if err := json.Unmarshal(raw, &objectIDs); err == nil {
		ids := make([]int, 0, len(objectIDs))
		for _, item := range objectIDs {
			ids = append(ids, item.ID)
		}
		return ids, nil
	}

	var generic []map[string]interface{}
	if err := json.Unmarshal(raw, &generic); err == nil {
		ids := make([]int, 0, len(generic))
		for _, item := range generic {
			value, ok := item["id"]
			if !ok {
				continue
			}
			switch typed := value.(type) {
			case float64:
				ids = append(ids, int(typed))
			case int:
				ids = append(ids, typed)
			case string:
				id, convErr := strconv.Atoi(typed)
				if convErr == nil {
					ids = append(ids, id)
				}
			}
		}
		return ids, nil
	}

	return nil, errors.New("unsupported list ids format")
}

// SendRequest sends a request to the specified Listmonk API endpoint
// with the provided method and data
// after authentication with the provided credentials (username, password)
func SendRequest(method string, url string, data interface{}, username string, password string) error {
	jsonData, err := json.Marshal(data)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	client := &http.Client{Timeout: listmonkRequestTimeout}
	req, err := http.NewRequest(method, url, bytes.NewBuffer(jsonData))
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	req.SetBasicAuth(username, password)
	req.Header.Set("Content-Type", "application/json")

	// Send request
	resp, err := client.Do(req)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, readErr := io.ReadAll(resp.Body)
		if readErr != nil {
			return stacktrace.Propagate(readErr, "")
		}
		return stacktrace.Propagate(
			fmt.Errorf("listmonk request failed with status %d: %s", resp.StatusCode, strings.TrimSpace(string(body))),
			"",
		)
	}

	return nil
}
