package repo

import (
	"strings"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/stretchr/testify/require"
)

func TestValidateSpaceSlugMatchesClientRules(t *testing.T) {
	for _, tc := range []struct {
		name       string
		input      string
		normalized string
	}{
		{name: "letters", input: "alice", normalized: "alice"},
		{name: "four chars", input: "four", normalized: "four"},
		{name: "numbers", input: "user123", normalized: "user123"},
		{name: "allowed separators", input: "my.space_name1", normalized: "my.space_name1"},
		{name: "normalizes case and spaces", input: " Alice_123 ", normalized: "alice_123"},
		{name: "thirty chars", input: strings.Repeat("a", 30), normalized: strings.Repeat("a", 30)},
	} {
		t.Run(tc.name, func(t *testing.T) {
			normalized, err := ValidateSpaceSlug(tc.input)
			require.NoError(t, err)
			require.Equal(t, tc.normalized, normalized)
		})
	}
}

func TestValidateSpaceSlugRejectsInvalidClientSlugs(t *testing.T) {
	for _, tc := range []struct {
		name    string
		input   string
		message string
	}{
		{name: "empty", input: " ", message: "spaceSlug is required"},
		{name: "too short", input: "abc", message: "spaceSlug must be 4-30 characters"},
		{name: "too long", input: strings.Repeat("a", 31), message: "spaceSlug must be 4-30 characters"},
		{name: "leading dot", input: ".alice", message: "spaceSlug can only contain"},
		{name: "leading dash", input: "-alice", message: "spaceSlug can only contain"},
		{name: "leading underscore", input: "_alice", message: "spaceSlug can only contain"},
		{name: "inner dash", input: "ali-ce", message: "spaceSlug can only contain"},
		{name: "space", input: "ali ce", message: "spaceSlug can only contain"},
		{name: "slash", input: "ali/ce", message: "spaceSlug can only contain"},
		{name: "control character", input: "ali\nce", message: "spaceSlug can only contain"},
		{name: "unicode confusable", input: "paypa\u217C", message: "spaceSlug can only contain"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, err := ValidateSpaceSlug(tc.input)
			require.Error(t, err)
			require.Contains(t, err.Error(), tc.message)
		})
	}
}

func TestValidateSpaceSlugAllowReservedAcceptsReservedSlug(t *testing.T) {
	normalized, err := ValidateSpaceSlugAllowReserved(" Ente ")
	require.NoError(t, err)
	require.Equal(t, "ente", normalized)
}

func TestValidateSpaceSlugRejectsReservedFileSuffix(t *testing.T) {
	_, err := ValidateSpaceSlug("theme.css")
	require.Error(t, err)
	require.Equal(t, spaceSlugReservedErrorCode, err.(*ente.ApiError).Code)
	require.Contains(t, err.Error(), "spaceSlug is reserved")
}
