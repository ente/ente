package ente

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"github.com/ente/stacktrace"
	"golang.org/x/net/idna"
)

type GetValueRequest struct {
	Key          string  `form:"key" binding:"required"`
	DefaultValue *string `form:"defaultValue"`
}

type GetValueResponse struct {
	Value string `json:"value" binding:"required"`
}

type UpdateKeyValueRequest struct {
	Key   string  `json:"key" binding:"required"`
	Value *string `json:"value" binding:"required"`
}

type AdminUpdateKeyValueRequest struct {
	UserID int64   `json:"userID" binding:"required"`
	Key    string  `json:"key" binding:"required"`
	Value  *string `json:"value" binding:"required"`
}

type FeatureFlagResponse struct {
	EnableStripe bool `json:"enableStripe"`
	// If true, the mobile client will stop using CF worker to download files
	DisableCFWorker     bool    `json:"disableCFWorker"`
	MapEnabled          bool    `json:"mapEnabled"`
	FaceSearchEnabled   bool    `json:"faceSearchEnabled"`
	PassKeyEnabled      bool    `json:"passKeyEnabled"`
	RecoveryKeyVerified bool    `json:"recoveryKeyVerified"`
	InternalUser        bool    `json:"internalUser"`
	BetaUser            bool    `json:"betaUser"`
	EnableMobMultiPart  bool    `json:"enableMobMultiPart"`
	ServerApiFlag       int64   `json:"serverApiFlag"`
	CastUrl             string  `json:"castUrl"`
	EmbedUrl            string  `json:"embedUrl"`
	CustomDomain        *string `json:"customDomain,omitempty"`
	CustomDomainCNAME   string  `json:"customDomainCNAME,omitempty"`
}

const (
	// UploadV2 marks availability of the upload v2 APIs in the binary.
	UploadV2 int64 = 1 << 0
	// Comments marks availability of the comments feature.
	Comments int64 = 1 << 1
	// BackupOptions marks availability of backup option features for older clients.
	BackupOptions int64 = 1 << 2
	// VideoStreaming gates video streaming feature.
	VideoStreaming int64 = 1 << 3
	// 1 << 4 previously gated CastSessionsV2 for released clients. Reuse it
	// only when those clients no longer need to be isolated from a new flag.
	// CastSessionsV2 gates cast sessions v2 support.
	CastSessionsV2 int64 = 1 << 5
)

type FlagKey string

const (
	RecoveryKeyVerified FlagKey = "recoveryKeyVerified"
	MapEnabled          FlagKey = "mapEnabled"
	FaceSearchEnabled   FlagKey = "faceSearchEnabled"
	PassKeyEnabled      FlagKey = "passKeyEnabled"
	IsInternalUser      FlagKey = "internalUser"
	IsBetaUser          FlagKey = "betaUser"
	CustomDomain        FlagKey = "customDomain"
)

var validFlagKeys = map[FlagKey]struct{}{
	RecoveryKeyVerified: {},
	MapEnabled:          {},
	FaceSearchEnabled:   {},
	PassKeyEnabled:      {},
	IsInternalUser:      {},
	IsBetaUser:          {},
	CustomDomain:        {},
}

func IsValidFlagKey(key string) bool {
	_, exists := validFlagKeys[FlagKey(key)]
	return exists
}

func (k FlagKey) String() string {
	return string(k)
}

// UserEditable returns true if the key is user editable
func (k FlagKey) UserEditable() bool {
	switch k {
	case RecoveryKeyVerified, MapEnabled, FaceSearchEnabled, PassKeyEnabled, CustomDomain:
		return true
	default:
		return false
	}
}

func (k FlagKey) NeedSubscription() bool {
	return false
}

func (k FlagKey) CanRemove() bool {
	return k == CustomDomain
}

func (k FlagKey) IsAdminEditable() bool {
	switch k {
	case RecoveryKeyVerified, MapEnabled, FaceSearchEnabled:
		return false
	case IsInternalUser, IsBetaUser, PassKeyEnabled:
		return true
	default:
		return true
	}
}

func (k FlagKey) IsBoolType() bool {
	switch k {
	case RecoveryKeyVerified, MapEnabled, FaceSearchEnabled, PassKeyEnabled, IsInternalUser, IsBetaUser:
		return true
	case CustomDomain:
		return false
	default:
		return false // Explicitly handle unexpected cases
	}
}

func (k FlagKey) IsValidValue(value string) error {
	if k.IsBoolType() && value != "true" && value != "false" {
		return stacktrace.Propagate(NewBadRequestWithMessage(fmt.Sprintf("value %s is not allowed", value)), "value not allowed")
	}
	if k == CustomDomain && value != "" {
		if _, _, isPointer, err := ParseFamilyCustomDomainPointer(value); err != nil {
			return stacktrace.Propagate(err, "invalid custom domain")
		} else if !isPointer {
			if err := isValidDomainWithoutScheme(value); err != nil {
				return stacktrace.Propagate(err, "invalid custom domain")
			}
		}
	}
	return nil
}

var domainRegex = regexp.MustCompile(`^(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$`)

func ValidatePublicCustomDomain(value string) error {
	return isValidDomainWithoutScheme(value)
}

const customDomainFamilyPrefix = "_"

// BuildFamilyCustomDomainPointer builds a member-scoped custom domain pointer
// to keep the custom domain unique across family members.
func BuildFamilyCustomDomainPointer(memberID int64, domain string) string {
	return fmt.Sprintf("%s%d:%s", customDomainFamilyPrefix, memberID, domain)
}

// ParseFamilyCustomDomainPointer parses a custom domain pointer of the form _<userID>:<domain>.
// Returns (userID, domain, isPointer, error).
func ParseFamilyCustomDomainPointer(value string) (int64, string, bool, error) {
	if !strings.HasPrefix(value, customDomainFamilyPrefix) {
		return 0, "", false, nil
	}
	trimmed := strings.TrimPrefix(value, customDomainFamilyPrefix)
	parts := strings.SplitN(trimmed, ":", 2)
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return 0, "", true, NewBadRequestWithMessage("invalid family custom domain format")
	}
	memberID, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil || memberID <= 0 {
		return 0, "", true, NewBadRequestWithMessage("invalid family custom domain user id")
	}
	domain := parts[1]
	if err := isValidDomainWithoutScheme(domain); err != nil {
		return 0, "", true, err
	}
	return memberID, domain, true, nil
}

// ResolveCustomDomainValue returns the effective domain for a custom domain value.
func ResolveCustomDomainValue(value string) (string, error) {
	if value == "" {
		return "", nil
	}
	_, domain, isPointer, err := ParseFamilyCustomDomainPointer(value)
	if err != nil {
		return "", err
	}
	if isPointer {
		return domain, nil
	}
	return value, nil
}

func isValidDomainWithoutScheme(input string) error {
	trimmed := strings.TrimSpace(input)
	if trimmed != input {
		return NewBadRequestWithMessage("domain contains leading or trailing spaces")
	}
	if trimmed == "" {
		return NewBadRequestWithMessage("domain is empty")
	}
	if strings.Contains(trimmed, "://") {
		return NewBadRequestWithMessage("domain should not contain scheme (e.g., http:// or https://)")
	}

	// Convert IDN to ASCII (Punycode) for validation
	asciiDomain, err := idna.ToASCII(trimmed)
	if err != nil {
		return NewBadRequestWithMessage(fmt.Sprintf("invalid idn domain format: %s", trimmed))
	}

	// Validate the ASCII version
	if !domainRegex.MatchString(asciiDomain) {
		return NewBadRequestWithMessage(fmt.Sprintf("invalid domain format: %s", trimmed))
	}

	return nil
}
