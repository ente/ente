package public

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"

	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/golang-jwt/jwt/v4"
)

const (
	LinkDeviceScopeCollection = "collection"
	LinkDeviceScopeFile       = "file"

	linkDeviceTokenType          = "link-device"
	linkDeviceTokenIssuer        = "museum"
	linkDeviceTokenAudience      = "public-link-device"
	linkDeviceTokenTTL           = 365
	LinkDeviceTokenRefreshBefore = 30 * 24 * time.MicroSecondsInOneHour
)

// LinkDeviceClaim represents a signed browser admission token for public links.
type LinkDeviceClaim struct {
	Typ             string `json:"typ"`
	Scope           string `json:"scope"`
	LinkID          string `json:"linkID"`
	AccessTokenHMAC string `json:"ath"`
	IssuedAt        int64  `json:"iat"`
	ExpiryTime      int64  `json:"exp"`
	Issuer          string `json:"iss"`
	Audience        string `json:"aud"`
}

func (c LinkDeviceClaim) Valid() error {
	if c.ExpiryTime < time.Microseconds() {
		return errors.New("token expired")
	}
	return nil
}

func NewLinkDeviceToken(secret []byte, scope string, linkID string, accessToken string, validTill int64) (string, int64, error) {
	now := time.Microseconds()
	expiry := time.NDaysFromNow(linkDeviceTokenTTL)
	if validTill > 0 && validTill < expiry {
		expiry = validTill
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, &LinkDeviceClaim{
		Typ:             linkDeviceTokenType,
		Scope:           scope,
		LinkID:          linkID,
		AccessTokenHMAC: linkDeviceAccessTokenHMAC(secret, accessToken),
		IssuedAt:        now,
		ExpiryTime:      expiry,
		Issuer:          linkDeviceTokenIssuer,
		Audience:        linkDeviceTokenAudience,
	})
	tokenString, err := token.SignedString(secret)
	return tokenString, expiry, stacktrace.Propagate(err, "failed to sign link device token")
}

func ValidateLinkDeviceToken(secret []byte, tokenString string, scope string, linkID string, accessToken string) (*LinkDeviceClaim, error) {
	token, err := jwt.ParseWithClaims(tokenString, &LinkDeviceClaim{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return secret, nil
	})
	if err != nil {
		return nil, stacktrace.Propagate(err, "link device token parse failed")
	}
	claim, ok := token.Claims.(*LinkDeviceClaim)
	if !ok || !token.Valid {
		return nil, stacktrace.NewError("invalid link device token")
	}
	if claim.Typ != linkDeviceTokenType ||
		claim.Scope != scope ||
		claim.LinkID != linkID ||
		claim.Issuer != linkDeviceTokenIssuer ||
		claim.Audience != linkDeviceTokenAudience {
		return nil, stacktrace.NewError("link device token claim mismatch")
	}
	expectedAccessTokenHMAC := linkDeviceAccessTokenHMAC(secret, accessToken)
	if !hmac.Equal([]byte(claim.AccessTokenHMAC), []byte(expectedAccessTokenHMAC)) {
		return nil, stacktrace.NewError("link device token access token mismatch")
	}
	return claim, nil
}

func linkDeviceAccessTokenHMAC(secret []byte, accessToken string) string {
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte("ente:public-link-device-token:access-token:v1"))
	mac.Write([]byte{0})
	mac.Write([]byte(accessToken))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}
