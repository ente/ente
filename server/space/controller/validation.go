package controller

import (
	"encoding/base64"
	"regexp"
	"strings"

	"github.com/ente/museum/ente"
)

const (
	minSpaceSlugLength                   = 4
	maxSpaceSlugLength                   = 30
	maxSpaceEncryptedProfileEncodedBytes = 32 * 1024
	maxSpaceEncryptedProfileDecodedBytes = 24 * 1024
	maxSpaceEncryptedKeyEncodedBytes     = 4 * 1024
	maxSpaceEncryptedKeyDecodedBytes     = 3 * 1024
	maxSpaceCaptionCipherEncodedBytes    = 16 * 1024
	maxSpaceCaptionCipherDecodedBytes    = 12 * 1024
	maxSpaceAssetMetadataEncodedBytes    = 8 * 1024
	maxSpaceAssetMetadataDecodedBytes    = 6 * 1024
	maxSpacePostObjects                  = 1
	maxSpaceFriendSharesPerRefresh       = 500
	maxSpaceObjectKeyBytes               = 512
)

var spaceSlugPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9._]*$`)
var reservedSpaceSlugs = newReservedSpaceSlugSet()

func normalizeSlug(input string) string {
	return strings.ToLower(strings.TrimSpace(input))
}

func newReservedSpaceSlugSet() map[string]struct{} {
	slugs := make(map[string]struct{}, len(reservedSpaceSlugList))
	for _, slug := range reservedSpaceSlugList {
		slugs[slug] = struct{}{}
	}
	return slugs
}

func validateSpaceSlug(input string) (string, error) {
	slug := normalizeSlug(input)
	if slug == "" {
		return "", ente.NewBadRequestWithMessage("spaceSlug is required")
	}
	if len(slug) < minSpaceSlugLength || len(slug) > maxSpaceSlugLength {
		return "", ente.NewBadRequestWithMessage("spaceSlug must be 4-30 characters")
	}
	if isReservedSpaceSlug(slug) {
		return "", ente.NewBadRequestWithMessage("spaceSlug is reserved")
	}
	if !spaceSlugPattern.MatchString(slug) {
		return "", ente.NewBadRequestWithMessage("spaceSlug can only contain lowercase letters, numbers, dots, or underscores, and must start with a letter or number")
	}
	return slug, nil
}

func isReservedSpaceSlug(slug string) bool {
	if _, ok := reservedSpaceSlugs[slug]; ok {
		return true
	}
	if strings.HasPrefix(slug, "ente") {
		return true
	}
	return strings.HasSuffix(slug, ".ente") || strings.HasSuffix(slug, "-ente") || strings.HasSuffix(slug, "_ente")
}

func decodeEncodedSpaceField(field string, value string, maxEncodedBytes int, maxDecodedBytes int) ([]byte, error) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return nil, ente.NewBadRequestWithMessage(field + " is required")
	}
	return decodeOptionalEncodedSpaceField(field, trimmed, maxEncodedBytes, maxDecodedBytes)
}

func decodeOptionalEncodedSpaceField(field string, value string, maxEncodedBytes int, maxDecodedBytes int) ([]byte, error) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return nil, nil
	}
	if len(trimmed) > maxEncodedBytes {
		return nil, ente.NewBadRequestWithMessage(field + " is too large")
	}
	decoded, err := base64.StdEncoding.DecodeString(trimmed)
	if err != nil || len(decoded) == 0 {
		return nil, ente.NewBadRequestWithMessage(field + " must be valid base64")
	}
	if len(decoded) > maxDecodedBytes {
		return nil, ente.NewBadRequestWithMessage(field + " is too large")
	}
	return decoded, nil
}

func decodeOptionalEncodedSpacePointerField(field string, value *string, maxEncodedBytes int, maxDecodedBytes int) ([]byte, error) {
	if value == nil {
		return nil, nil
	}
	return decodeOptionalEncodedSpaceField(field, *value, maxEncodedBytes, maxDecodedBytes)
}

func encodeSpaceField(value []byte) string {
	if len(value) == 0 {
		return ""
	}
	return base64.StdEncoding.EncodeToString(value)
}

func validateSpaceTextFieldBytes(field string, value string, maxBytes int) error {
	if len(strings.TrimSpace(value)) > maxBytes {
		return ente.NewBadRequestWithMessage(field + " is too large")
	}
	return nil
}
