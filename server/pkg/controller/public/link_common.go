package public

import (
	"errors"
	"fmt"
	"github.com/ente/museum/ente"
	enteJWT "github.com/ente/museum/ente/jwt"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/golang-jwt/jwt/v4"
)

func validateJWTToken(secret []byte, jwtToken string, passwordHash string) error {
	token, err := jwt.ParseWithClaims(jwtToken, &enteJWT.LinkPasswordClaim{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return stacktrace.Propagate(fmt.Errorf("unexpected signing method: %v", token.Header["alg"]), ""), nil
		}
		return secret, nil
	})
	if err != nil {
		return stacktrace.Propagate(err, "JWT parsed failed")
	}
	claims, ok := token.Claims.(*enteJWT.LinkPasswordClaim)

	if !ok {
		return stacktrace.Propagate(errors.New("no claim in jwt token"), "")
	}
	if token.Valid && claims.PassHash == passwordHash {
		return nil
	}
	return ente.ErrInvalidPassword
}

func verifyPassword(secret []byte, expectedPassHash *string, req ente.VerifyPasswordRequest) (*ente.VerifyPasswordResponse, error) {
	if expectedPassHash == nil || *expectedPassHash == "" {
		return nil, stacktrace.Propagate(ente.ErrBadRequest, "password is not configured for the link")
	}
	if req.PassHash != *expectedPassHash {
		return nil, stacktrace.Propagate(ente.ErrInvalidPassword, "incorrect password for link")
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, &enteJWT.LinkPasswordClaim{
		PassHash:   req.PassHash,
		ExpiryTime: time.NDaysFromNow(30),
	})
	// Sign and get the complete encoded token as a string using the secret
	tokenString, err := token.SignedString(secret)

	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &ente.VerifyPasswordResponse{
		JWTToken: tokenString,
	}, nil
}
