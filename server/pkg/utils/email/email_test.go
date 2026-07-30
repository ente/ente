package email

import (
	"io"
	"mime/quotedprintable"
	"strings"
	"testing"

	"github.com/ente/museum/internal/testutil"
	"github.com/stretchr/testify/assert"
)

func TestBuildHTMLMIMEPartPreservesUnicode(t *testing.T) {
	htmlBody := "<p>Hello – emoji 😊</p>"

	part, err := buildHTMLMIMEPart(htmlBody)
	assert.NoError(t, err)
	assert.Contains(t, part, "Content-Type: text/html; charset=utf-8")
	assert.Contains(t, part, "Content-Transfer-Encoding: quoted-printable")
	assert.Contains(t, part, "=E2=80=93")
	assert.Contains(t, part, "=F0=9F=98=8A")

	sections := strings.SplitN(part, "\n\n", 2)
	if assert.Len(t, sections, 2) {
		decodedBody, err := io.ReadAll(
			quotedprintable.NewReader(strings.NewReader(strings.TrimSuffix(sections[1], "\n"))),
		)
		assert.NoError(t, err)
		assert.Equal(t, htmlBody, string(decodedBody))
	}
}

func TestGetMaskedEmailForPublic(t *testing.T) {
	tests := []struct {
		name     string
		email    string
		expected string
	}{
		{
			name:     "standard email",
			email:    "john@example.io",
			expected: "jo**@e********o",
		},
		{
			name:     "gmail address",
			email:    "john.doe@gmail.com",
			expected: "jo******@g*******m",
		},
		{
			name:     "short username 2 chars",
			email:    "ab@example.com",
			expected: "ab@e*********m",
		},
		{
			name:     "short username 1 char",
			email:    "a@example.com",
			expected: "a@e*********m",
		},
		{
			name:     "short domain 2 chars",
			email:    "test@ab",
			expected: "te**@ab",
		},
		{
			name:     "short domain 1 char",
			email:    "test@a",
			expected: "te**@a",
		},
		{
			name:     "email with spaces trimmed",
			email:    "  user@domain.com  ",
			expected: "us**@d********m",
		},
		{
			name:     "invalid email no @",
			email:    "invalidemail",
			expected: "[invalid_email]",
		},
		{
			name:     "invalid email @ at start",
			email:    "@domain.com",
			expected: "[invalid_email]",
		},
		{
			name:     "invalid email @ at end",
			email:    "user@",
			expected: "[invalid_email]",
		},
		{
			name:     "empty string",
			email:    "",
			expected: "[invalid_email]",
		},
		{
			name:     "long username and domain",
			email:    "verylongusername@verylongdomain.org",
			expected: "ve**************@v****************g",
		},
		{
			name:     "unicode username",
			email:    "用户名@example.com",
			expected: "用户*@e*********m",
		},
		{
			name:     "unicode domain",
			email:    "test@例え.jp",
			expected: "te**@例***p",
		},
		{
			name:     "mixed unicode",
			email:    "日本語@ドメイン.jp",
			expected: "日本*@ド*****p",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := GetMaskedEmailForPublic(tt.email)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestInactiveUserDeletionTemplatesIncludeAccountEmail(t *testing.T) {
	testutil.WithServerRoot(t)

	templateData := map[string]interface{}{
		"Email":        "alice@example.com",
		"DeletionDate": "April 1, 2026",
	}
	templateNames := []string{
		"inactive-user-deletion/warn_2m.html",
		"inactive-user-deletion/warn_1m.html",
		"inactive-user-deletion/warn_7d.html",
		"inactive-user-deletion/warn_1d.html",
		"inactive-user-deletion/confirm_13m.html",
	}

	for _, templateName := range templateNames {
		t.Run(templateName, func(t *testing.T) {
			body, err := getMailBodyWithBase("ente_base.html", templateName, templateData)
			assert.NoError(t, err)
			assert.Contains(t, body, "alice@example.com")
		})
	}
}
