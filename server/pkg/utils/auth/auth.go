package auth

import (
	"crypto/rand"
	"encoding/base64"
	"math/big"
	"net/http"
	"strconv"
	"strings"

	"github.com/ente/museum/ente/cast"

	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

const (
	PublicAccessKey      = "X-Public-Access-ID"
	PublicAnonUserKey    = "X-Public-Anon-User-ID"
	FileLinkAccessKey    = "X-Public-FileLink-Access-ID"
	CastContext          = "X-Cast-Context"
	MemoryShareAccessKey = "X-Memory-Share-Access-ID"
	AppContextKey        = "auth.app"

	LinkDeviceTokenHeader         = "X-Auth-Link-Device-Token"
	LinkDeviceTokenResponseHeader = "X-Ente-Link-Device-Token"
	LinkDeviceTokenResponseKey    = "linkDeviceToken"
)

// GenerateRandomBytes returns securely generated random bytes.
func GenerateRandomBytes(n int) []byte {
	b := make([]byte, n)
	rand.Read(b)
	return b
}

// GenerateRandomInt returns a securely generated random integer in [0, n).
//
// It will return an error if the system's secure random number generator fails
// to function correctly, in which case the caller should not continue.
func GenerateRandomInt(n int64) (int64, error) {
	r, err := rand.Int(rand.Reader, big.NewInt(n))
	if err != nil {
		return 0, stacktrace.Propagate(err, "")
	}
	return r.Int64(), nil
}

// GenerateURLSafeRandomString returns a URL-safe, base64 encoded
// securely generated random string.
func GenerateURLSafeRandomString(s int) string {
	return base64.URLEncoding.EncodeToString(GenerateRandomBytes(s))
}

// GetHashedPassword returns the has of a specified password
func GetHashedPassword(password string) (string, error) {
	saltedBytes := []byte(password)
	hashedBytes, err := bcrypt.GenerateFromPassword(saltedBytes, bcrypt.DefaultCost)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}

	hash := string(hashedBytes[:])
	return hash, nil
}

// CompareHashes compares a bcrypt hashed password with its possible plaintext
// equivalent. Returns nil on success, or an error on failure.
func CompareHashes(hash string, s string) error {
	existing := []byte(hash)
	incoming := []byte(s)
	return bcrypt.CompareHashAndPassword(existing, incoming)
}

// GetUserID fetches the userID embedded in a request header
func GetUserID(header http.Header) int64 {
	userID, _ := strconv.ParseInt(header.Get("X-Auth-User-ID"), 10, 64)
	return userID
}

func GetApp(c *gin.Context) ente.App {
	if strings.HasPrefix(c.GetHeader("X-Client-Package"), "io.ente.auth") {
		return ente.Auth
	}

	if strings.HasPrefix(c.GetHeader("X-Client-Package"), "io.ente.locker") {
		return ente.Locker
	}

	return ente.Photos
}

func GetAuthenticatedApp(c *gin.Context) (ente.App, bool) {
	app, ok := c.Get(AppContextKey)
	if !ok {
		return "", false
	}
	enteApp, ok := app.(ente.App)
	return enteApp, ok
}

func GetToken(c *gin.Context) string {
	token := c.GetHeader("X-Auth-Token")
	if token == "" {
		token = c.Query("token")
	}
	return token
}

func GetAccessToken(c *gin.Context) string {
	token := c.GetHeader("X-Auth-Access-Token")
	if token == "" {
		token = c.Query("accessToken")
	}
	return token
}

func GetCastToken(c *gin.Context) string {
	token := c.GetHeader("X-Cast-Access-Token")
	if token == "" {
		token = c.Query("castToken")
	}
	return token
}

// GetAccessTokenJWT fetches the JWT access token from the request header or query parameters.
// This token is issued by server on password verification of links that are protected by password.
func GetAccessTokenJWT(c *gin.Context) string {
	token := c.GetHeader("X-Auth-Access-Token-JWT")
	if token == "" {
		token = c.Query("accessTokenJWT")
	}
	return token
}

func GetLinkDeviceToken(c *gin.Context) string {
	return c.GetHeader(LinkDeviceTokenHeader)
}

func MustGetPublicAccessContext(c *gin.Context) ente.PublicAccessContext {
	return c.MustGet(PublicAccessKey).(ente.PublicAccessContext)
}

func SetPublicAnonUserID(c *gin.Context, anonID string) {
	c.Set(PublicAnonUserKey, anonID)
}

func GetPublicAnonUserID(c *gin.Context) (*string, bool) {
	value, ok := c.Get(PublicAnonUserKey)
	if !ok {
		return nil, false
	}
	if anonID, ok := value.(string); ok {
		copyID := anonID
		return &copyID, true
	}
	return nil, false
}

func MustGetFileLinkAccessContext(c *gin.Context) *ente.FileLinkAccessContext {
	return c.MustGet(FileLinkAccessKey).(*ente.FileLinkAccessContext)
}

func GetCastCtx(c *gin.Context) cast.AuthContext {
	return c.MustGet(CastContext).(cast.AuthContext)
}

func MustGetMemoryShareAccessContext(c *gin.Context) ente.MemoryShareAccessContext {
	return c.MustGet(MemoryShareAccessKey).(ente.MemoryShareAccessContext)
}
