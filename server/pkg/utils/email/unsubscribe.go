package email

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"net"
	"net/url"
	"strconv"
	"strings"

	"github.com/ente/museum/ente"
)

type UnsubscribeLinks struct {
	endpoint url.URL
	keys     [][]byte
}

func NewUnsubscribeLinks(publicURL string, signingKeys []string) (*UnsubscribeLinks, error) {
	if publicURL == "" && len(signingKeys) == 0 {
		return nil, nil
	}
	base, err := url.Parse(publicURL)
	if err != nil || base.Hostname() == "" || base.User != nil || base.RawQuery != "" || base.Fragment != "" {
		return nil, errors.New("invalid email-subscriptions.public-url")
	}
	if base.Scheme != "https" &&
		!(base.Scheme == "http" && (base.Hostname() == "localhost" || net.ParseIP(base.Hostname()).IsLoopback())) {
		return nil, errors.New("email-subscriptions.public-url requires HTTPS outside localhost")
	}
	if len(signingKeys) == 0 {
		return nil, errors.New("email-subscriptions.unsubscribe-signing-keys is empty")
	}
	keys := make([][]byte, len(signingKeys))
	for i, key := range signingKeys {
		if len(key) < 32 {
			return nil, fmt.Errorf("email unsubscribe signing key %d must have at least 32 bytes", i+1)
		}
		keys[i] = []byte(key)
	}
	endpoint := base.JoinPath("email", "unsubscribe")
	return &UnsubscribeLinks{endpoint: *endpoint, keys: keys}, nil
}

func (l *UnsubscribeLinks) URL(userID int64, emailType ente.EmailType) string {
	payload := strconv.FormatInt(userID, 10) + "." + string(emailType)
	signature := base64.RawURLEncoding.EncodeToString(signUnsubscribe(l.keys[0], payload))
	endpoint := l.endpoint
	endpoint.RawQuery = url.Values{"token": {payload + "." + signature}}.Encode()
	return endpoint.String()
}

func (l *UnsubscribeLinks) Verify(token string) (int64, ente.EmailType, bool) {
	if l == nil || len(token) > 128 {
		return 0, "", false
	}
	user, rest, _ := strings.Cut(token, ".")
	category, signature, _ := strings.Cut(rest, ".")
	userID, err := strconv.ParseInt(user, 10, 64)
	emailType := ente.EmailType(category)
	if err != nil || userID <= 0 || emailType.Label() == "" {
		return 0, "", false
	}
	expected, err := base64.RawURLEncoding.Strict().DecodeString(signature)
	if err != nil {
		return 0, "", false
	}
	for _, key := range l.keys {
		if hmac.Equal(expected, signUnsubscribe(key, user+"."+category)) {
			return userID, emailType, true
		}
	}
	return 0, "", false
}

func signUnsubscribe(key []byte, payload string) []byte {
	mac := hmac.New(sha256.New, key)
	mac.Write([]byte("ente:email-unsubscribe:v1:"))
	mac.Write([]byte(payload))
	return mac.Sum(nil)
}
