package repo

import (
	"strings"
	"testing"

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

func TestValidateSpaceSlugAllowReservedOnlyBypassesReservedCheck(t *testing.T) {
	normalized, err := ValidateSpaceSlugAllowReserved(" Ente ")
	require.NoError(t, err)
	require.Equal(t, "ente", normalized)

	_, err = ValidateSpaceSlugAllowReserved("ente-user")
	require.Error(t, err)
	require.Contains(t, err.Error(), "spaceSlug can only contain")

	_, err = ValidateSpaceSlugAllowReserved("ali/ce")
	require.Error(t, err)
	require.Contains(t, err.Error(), "spaceSlug can only contain")

	_, err = ValidateSpaceSlugAllowReserved("abc")
	require.Error(t, err)
	require.Contains(t, err.Error(), "spaceSlug must be 4-30 characters")
}

func TestReservedSpaceSlugListBuildsLookup(t *testing.T) {
	seen := make(map[string]struct{}, len(reservedSpaceSlugList))
	for _, slug := range reservedSpaceSlugList {
		require.Equal(t, slug, normalizeSlug(slug))

		_, ok := seen[slug]
		require.False(t, ok, "duplicate reserved space slug: %s", slug)
		seen[slug] = struct{}{}

		_, ok = reservedSpaceSlugs[slug]
		require.True(t, ok, "missing reserved space slug lookup: %s", slug)
	}
	require.Len(t, reservedSpaceSlugs, len(reservedSpaceSlugList))
}

func TestValidateSpaceSlugRejectsReservedSlugs(t *testing.T) {
	for _, slug := range []string{
		"404",
		"about",
		"administration",
		"apple-photos-alternative",
		"archives",
		"architecture",
		"articles",
		"auth",
		"auth-ph",
		"blackfriday",
		"blog",
		"blue",
		"careers",
		"cli",
		"compare",
		"contact",
		"customers",
		"desktop",
		"discord",
		"documentation",
		"download",
		"encryption",
		"ensu",
		"families",
		"features",
		"fosdem",
		"get",
		"github",
		"google-photos-alternative",
		"green",
		"help",
		"hunt",
		"install",
		"installation",
		"instance",
		"intern",
		"jobs",
		"locker",
		"machine-learning",
		"manifest",
		"manifest.webmanifest",
		"media-kit",
		"mobile",
		"moderators",
		"mods",
		"news",
		"newsletter",
		"paste",
		"photos",
		"photo-backup-for-families",
		"press",
		"pricing",
		"privacy",
		"profile",
		"profile-link",
		"rate",
		"reliability",
		"replication",
		"rss",
		"rss.xml",
		"server",
		"shop",
		"space",
		"support",
		"take-control",
		"talks",
		"terms",
		"toys",
		"translate",
		"try",
		"ente",
		"ente-user",
	} {
		t.Run(slug, func(t *testing.T) {
			_, err := ValidateSpaceSlug(slug)
			require.Error(t, err)
			if len(slug) < minSpaceSlugLength {
				require.Contains(t, err.Error(), "spaceSlug must be 4-30 characters")
			} else {
				require.Contains(t, err.Error(), "spaceSlug is reserved")
			}
		})
	}
}

func TestValidateSpaceSlugRejectsPhishingSlugs(t *testing.T) {
	for _, slug := range []string{
		"2fa",
		"account-recovery",
		"account-security",
		"account-verification",
		"account-verify",
		"app-download",
		"authenticate",
		"authenticated",
		"authenticator",
		"authorization",
		"authorize",
		"backup",
		"backups",
		"bill",
		"billing",
		"callback",
		"checkout",
		"contact-support",
		"customer-support",
		"download-app",
		"download-ente",
		"downloads",
		"email-verification",
		"export",
		"forgot",
		"forgot-password",
		"forgot_password",
		"get-app",
		"get-ente",
		"get-started",
		"getting-started",
		"help-desk",
		"helpdesk",
		"import",
		"install-app",
		"install-ente",
		"installer",
		"installers",
		"log-in",
		"log.in",
		"log_in",
		"log-off",
		"log.off",
		"log_off",
		"log-on",
		"log.on",
		"log_on",
		"log-out",
		"log.out",
		"log_out",
		"logoff",
		"logon",
		"magic-link",
		"magic_link",
		"mfa",
		"migration",
		"oauth",
		"oauth2",
		"onboarding",
		"otp",
		"passkey",
		"password",
		"password-reset",
		"passwords",
		"pay",
		"payment",
		"payments",
		"plan",
		"plans",
		"recovery",
		"reset",
		"reset-password",
		"restore",
		"secure",
		"secure-login",
		"secure-sign-in",
		"session",
		"sessions",
		"setup",
		"setup-account",
		"sign-in",
		"sign.in",
		"sign_in",
		"sign-on",
		"sign.on",
		"sign_on",
		"sign-out",
		"sign.out",
		"sign_out",
		"sign-up",
		"sign.up",
		"sign_up",
		"start",
		"started",
		"subscribe",
		"subscription",
		"subscriptions",
		"support-team",
		"support_team",
		"token",
		"tokens",
		"totp",
		"upgrade",
		"verification",
		"verify-account",
		"verify-email",
		"welcome",
		"ente.space",
		"space.ente",
		"space-ente",
		"space_ente",
		"login.ente",
		"support.ente",
	} {
		t.Run(slug, func(t *testing.T) {
			_, err := ValidateSpaceSlug(slug)
			require.Error(t, err)
			if len(slug) < minSpaceSlugLength {
				require.Contains(t, err.Error(), "spaceSlug must be 4-30 characters")
			} else {
				require.Contains(t, err.Error(), "spaceSlug is reserved")
			}
		})
	}
}
