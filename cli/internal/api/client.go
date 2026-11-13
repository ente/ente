package api

import (
	"bytes"
	"context"
	"fmt"
	"github.com/go-resty/resty/v2"
	"log"
	"net/url"
	"strings"
	"time"
)

const (
	EnteAPIEndpoint = "https://api.ente.com"
	TokenHeader     = "X-Auth-Token"
	TokenQuery      = "token"
	ClientPkgHeader = "X-Client-Package"
)

var (
	RedactedHeaders = []string{TokenHeader, " X-Request-Id"}
)
var tokenMap map[string]string = make(map[string]string)

type Client struct {
	restClient     *resty.Client
	downloadClient *resty.Client
}

type Params struct {
	Debug bool
	Trace bool
	Host  string
}

func readValueFromContext(ctx context.Context, key string) interface{} {
	value := ctx.Value(key)
	return value
}

func NewClient(p Params) *Client {
	enteAPI := resty.New()

	if p.Trace {
		enteAPI.EnableTrace()
	}
	enteAPI.OnBeforeRequest(func(c *resty.Client, req *resty.Request) error {
		app := readValueFromContext(req.Context(), "app")
		if app == nil {
			panic("app not set in context")
		}
		req.Header.Set(ClientPkgHeader, StringToApp(app.(string)).ClientPkg())
		attachToken(req)
		return nil
	})
	if p.Debug {
		enteAPI.OnBeforeRequest(func(c *resty.Client, req *resty.Request) error {
			logRequest(req)
			return nil
		})

		enteAPI.OnAfterResponse(func(c *resty.Client, resp *resty.Response) error {
			logResponse(resp)
			return nil
		})
	}
	if p.Host != "" {
		enteAPI.SetBaseURL(p.Host)
	} else {
		enteAPI.SetBaseURL(EnteAPIEndpoint)
	}
	return &Client{
		restClient: enteAPI,
		downloadClient: resty.New().
			SetRetryCount(3).
			SetRetryWaitTime(10 * time.Second).
			SetRetryMaxWaitTime(20 * time.Second).
			AddRetryCondition(func(r *resty.Response, err error) bool {
				shouldRetry := r.StatusCode() == 429 || r.StatusCode() >= 500
				if shouldRetry {
					amxRequestID := r.Header().Get("X-Amz-Request-Id")
					cfRayID := r.Header().Get("CF-Ray")
					wasabiRefID := r.Header().Get("X-Wasabi-Cm-Reference-Id")
					log.Printf("Retry scheduled. error statusCode: %d, X-Amz-Request-Id: %s, CF-Ray: %s, X-Wasabi-Cm-Reference-Id: %s", r.StatusCode(), amxRequestID, cfRayID, wasabiRefID)
				}
				return shouldRetry
			}),
	}
}

func attachToken(req *resty.Request) {
	accountKey := readValueFromContext(req.Context(), "account_key")
	if accountKey != nil && accountKey != "" {
		if token, ok := tokenMap[accountKey.(string)]; ok {
			req.SetHeader(TokenHeader, token)
		}
	}
}

func (c *Client) AddToken(id string, token string) {
	tokenMap[id] = token
}

func (c *Client) ValidateAuthToken(token []byte) error {
	endpoint, err := url.Parse(c.restClient.BaseURL)
	if err != nil {
		return err
	}
	switch strings.ToLower(endpoint.Hostname()) {
	case "api.ente.com", "api.ente.in", "localhost":
		if len(token) != len("auth-token")+32 || !bytes.HasPrefix(token, []byte("auth-token")) {
			return fmt.Errorf("invalid login token")
		}
	}
	return nil
}
