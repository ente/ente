package ente

import (
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v4"
)

const anonIdentityTokenType = "anon-identity"

type AnonymousIdentityClaim struct {
	Typ string `json:"typ"`
	jwt.RegisteredClaims
}

func NewAnonymousIdentityToken(secret []byte, anonUserID string) (string, int64, error) {
	issuedAt := time.Now()
	expiry := issuedAt.AddDate(1, 0, 0)
	claim := AnonymousIdentityClaim{
		Typ: anonIdentityTokenType,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   anonUserID,
			Issuer:    "museum",
			IssuedAt:  jwt.NewNumericDate(issuedAt),
			ExpiresAt: jwt.NewNumericDate(expiry),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claim)
	tokenString, err := token.SignedString(secret)
	if err != nil {
		return "", 0, err
	}
	return tokenString, MicrosecondsFromTime(expiry), nil
}

func ParseAnonymousIdentityToken(secret []byte, tokenString string) (*AnonymousIdentityClaim, error) {
	token, err := jwt.ParseWithClaims(tokenString, &AnonymousIdentityClaim{}, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return secret, nil
	})
	if err != nil {
		return nil, err
	}
	claim, ok := token.Claims.(*AnonymousIdentityClaim)
	if !ok || !token.Valid || claim.Typ != anonIdentityTokenType {
		return nil, fmt.Errorf("invalid anonymous identity token")
	}
	if claim.Subject == "" {
		return nil, fmt.Errorf("missing subject in anonymous identity token")
	}
	return claim, nil
}

func MicrosecondsFromTime(t time.Time) int64 {
	return t.UnixNano() / 1000
}
