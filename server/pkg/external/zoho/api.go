// The zoho package contains wrappers for the (generic) Zoho API.
//
// These are stateless functions that wrap over the HTTP calls that need to be
// made to obtain data from the Zoho HTTP API. In particular, they contain the
// code for dealing with access tokens and their renewal.
package zoho

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	"github.com/ente/stacktrace"
	log "github.com/sirupsen/logrus"
)

// The minimum credentials we need to obtain valid access tokens.
//
// To generate these credentials:
//
// Create new client in https://api-console.zoho.com/. Use client type
// "Self-client". This gives us the client id and client secret.
//
// Generate an (authorization) code with scope "ZohoCampaigns.contact.WRITE" and
// portal "Campaigns".
//
// Use this authorization code to obtain a refresh/access token pair. Note that
// we don't have a redirect_uri, so we just use the dummy one that is given in
// their documentation examples elsewhere.
// (https://www.zoho.com/accounts/protocol/oauth/web-apps/access-token.html)
//
//	curl -X POST \
//	 'https://accounts.zoho.com/oauth/v2/token? \
//	 client_id=xxx&grant_type=authorization_code&client_secret=yyy \
//	 &redirect_uri=https://www.zylker.com/oauthredirect&code=zzz'
//
// Save the refresh token. We can later use it to regenerate the access token
// (Zoho access tokens have a short, 1 hour validity anyway).
type Credentials struct {
	ClientID     string
	ClientSecret string
	RefreshToken string
}

// Do an HTTP `method` request to `url` using the given accessToken.
//
// If the accessToken has expired, use the given credentials to renew it.
//
// Return the accessToken (renewed or original) that gets used, and any errors
// that occurred. If the API returns `status` "success", then error will be nil.
func DoRequest(method string, url string, accessToken string, credentials Credentials) (string, error) {
	ar, err := doRequestNoRetry(method, url, accessToken, credentials)
	if err != nil {
		return accessToken, stacktrace.Propagate(err, "")
	}

	// Code 1007 indicates that the access token has expired
	// ("message":"Unauthorized request.")
	if ar.Status == "error" && ar.Code == "1007" {
		accessToken, err = renewAccessToken(credentials)
		if err != nil {
			return accessToken, stacktrace.Propagate(err, "")
		}

		// Try again
		ar, err = doRequestNoRetry(method, url, accessToken, credentials)
		if err != nil {
			return accessToken, stacktrace.Propagate(err, "")
		}
	}

	if ar.Status == "success" {
		return accessToken, nil
	}

	// Something else went wrong
	return accessToken, stacktrace.NewError(
		"Zoho API returned an non-success status %s (code %s: %s)",
		ar.Status, ar.Code, ar.Message)
}

// The basic generic fields that we expect in a response from Zoho APIs
type genericAPIResponse struct {
	Status  string `json:"status"`
	Code    string `json:"Code"`
	Message string `json:"message"`
}

func doRequestNoRetry(method string, url string, accessToken string, credentials Credentials) (genericAPIResponse, error) {
	var ar genericAPIResponse

	client := &http.Client{}
	req, err := http.NewRequest(method, url, nil)
	if err != nil {
		return ar, stacktrace.Propagate(err, "")
	}

	req.Header.Set("Accept", "application/json")
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", accessToken))
	res, err := client.Do(req)
	if err != nil {
		return ar, stacktrace.Propagate(err, "")
	}

	if res.Body != nil {
		defer res.Body.Close()
	}

	body, err := io.ReadAll(res.Body)
	if err != nil {
		return ar, stacktrace.Propagate(err, "")
	}

	log.Infof("Zoho %s %s response: %s", method, url, body)

	err = json.Unmarshal(body, &ar)
	return ar, stacktrace.Propagate(err, "")
}

// Obtain a new access token using the given credentials
func renewAccessToken(credentials Credentials) (string, error) {
	// https://www.zoho.com/crm/developer/docs/api/v3/refresh.html
	url := fmt.Sprintf(
		"https://accounts.zoho.com/oauth/v2/token?refresh_token=%s&client_id=%s&client_secret=%s&grant_type=refresh_token",
		credentials.RefreshToken, credentials.ClientID, credentials.ClientSecret)

	type jsonResponse struct {
		AccessToken string `json:"access_token"`
	}

	res, err := http.Post(url, "application/json", nil)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}

	if res.Body != nil {
		defer res.Body.Close()
	}

	body, err := io.ReadAll(res.Body)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}

	var jr jsonResponse
	err = json.Unmarshal(body, &jr)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}

	log.Infof("Renewed Zoho access token")

	return jr.AccessToken, nil
}
