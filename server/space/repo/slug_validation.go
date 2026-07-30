package repo

import (
	"regexp"
	"strings"

	"github.com/ente/museum/ente"
)

const (
	minSpaceSlugLength = 4
	maxSpaceSlugLength = 30
)

var spaceSlugPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9._]*$`)
var reservedSpaceSlugs = newReservedSpaceSlugSet()

func newReservedSpaceSlugSet() map[string]struct{} {
	slugs := make(map[string]struct{}, len(reservedSpaceSlugList))
	for _, slug := range reservedSpaceSlugList {
		slugs[slug] = struct{}{}
	}
	return slugs
}

func ValidateSpaceSlug(input string) (string, error) {
	return validateSpaceSlug(input, false)
}

func ValidateSpaceSlugAllowReserved(input string) (string, error) {
	return validateSpaceSlug(input, true)
}

func validateSpaceSlug(input string, allowReserved bool) (string, error) {
	slug := normalizeSlug(input)
	if slug == "" {
		return "", ente.NewBadRequestWithMessage("spaceSlug is required")
	}
	if len(slug) < minSpaceSlugLength || len(slug) > maxSpaceSlugLength {
		return "", ente.NewBadRequestWithMessage("spaceSlug must be 4-30 characters")
	}
	if !allowReserved && isReservedSpaceSlug(slug) {
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
