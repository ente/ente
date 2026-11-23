package postmark

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

const MaxBatchSize = 500

type Client struct {
	ServerToken string
	From        string
}

type Header struct {
	Name  string
	Value string
}

type Message struct {
	From          string
	To            string
	Subject       string
	HTMLBody      string `json:"HtmlBody"`
	MessageStream string
	TrackLinks    string
	Headers       []Header
}

var httpClient = &http.Client{
	Timeout: 30 * time.Second,
	CheckRedirect: func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	},
}

func (c Client) SendBatch(ctx context.Context, messages []Message) ([]int, error) {
	for i := range messages {
		messages[i].From = c.From
	}
	payload, err := json.Marshal(messages)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://api.postmarkapp.com/email/batch", bytes.NewReader(payload))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Postmark-Server-Token", c.ServerToken)
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("Postmark batch returned HTTP %d", resp.StatusCode)
	}

	var results []struct {
		ErrorCode int
	}
	if err := json.NewDecoder(resp.Body).Decode(&results); err != nil {
		return nil, err
	}
	if len(results) != len(messages) {
		return nil, fmt.Errorf("Postmark returned %d results for %d messages", len(results), len(messages))
	}
	codes := make([]int, len(results))
	for i, result := range results {
		codes[i] = result.ErrorCode
	}
	return codes, nil
}
