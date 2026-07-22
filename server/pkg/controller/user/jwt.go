package user

import (
	"errors"
	"fmt"
	"net/http"

	"github.com/ente/museum/ente"
	enteJWT "github.com/ente/museum/ente/jwt"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/golang-jwt/jwt/v4"
)

// jwt token validity = 1 day
const ValidForDays = 1

var errJWTExpired = &ente.ApiError{
	Code:           ente.BadRequest,
	Message:        "token expired",
	HttpStatusCode: http.StatusBadRequest,
}

func (c *UserController) GetJWTToken(userID int64, scope enteJWT.ClaimScope) (string, error) {
	tokenExpiry := time.NDaysFromNow(1)
	if scope == enteJWT.ACCOUNTS {
		tokenExpiry = time.NMinFromNow(30)
	}
	claim := enteJWT.WebCommonJWTClaim{
		UserID:     userID,
		ExpiryTime: tokenExpiry,
		ClaimScope: &scope,
	}
	return c.GetJWTTokenForClaim(&claim)
}

func (c *UserController) GetJWTTokenForClaim(claim *enteJWT.WebCommonJWTClaim) (string, error) {
	// Create a new token object, specifying signing method and the claims
	// you would like it to contain.
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claim)
	// Sign and get the complete encoded token as a string using the secret
	tokenString, err := token.SignedString(c.JwtSecret)

	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	return tokenString, nil
}

func (c *UserController) ValidateJWTToken(jwtToken string, scope enteJWT.ClaimScope) (*enteJWT.WebCommonJWTClaim, error) {
	token, err := jwt.ParseWithClaims(jwtToken, &enteJWT.WebCommonJWTClaim{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, stacktrace.Propagate(fmt.Errorf("unexpected signing method: %v", token.Header["alg"]), "")
		}
		return c.JwtSecret, nil
	})
	if err != nil {
		if errors.Is(err, enteJWT.ErrTokenExpired) {
			return nil, stacktrace.Propagate(errJWTExpired, "")
		}
		return nil, stacktrace.Propagate(err, "JWT parsed failed")
	}
	claims, ok := token.Claims.(*enteJWT.WebCommonJWTClaim)
	if ok && token.Valid {
		if claims.GetScope() != scope {
			return nil, stacktrace.Propagate(fmt.Errorf("recived claimScope %s is different than expected scope: %s", claims.GetScope(), scope), "")
		}
		return claims, nil
	}
	return nil, stacktrace.Propagate(err, "JWT claim failed")
}
