package email

import (
	"testing"

	"github.com/ente/museum/internal/testutil"
	"github.com/stretchr/testify/assert"
)

func TestStorageWarningTemplatesIncludeAccountEmail(t *testing.T) {
	testutil.WithServerRoot(t)

	templateData := map[string]interface{}{
		"AccountEmail":   "alerts@example.com",
		"AutoDeleteDate": "April 1, 2026",
		"ExpiryDate":     "March 1, 2026",
		"GraceUntil":     "April 8, 2026 at 12:00 UTC",
		"GraceDays":      7,
	}
	templateNames := []string{
		"storage-warning/storage_warning_active_overage.html",
		"storage-warning/storage_warning_expired.html",
		"storage-warning/storage_warning_login_grace.html",
	}

	for _, templateName := range templateNames {
		t.Run(templateName, func(t *testing.T) {
			body, err := getMailBodyWithBase("base.html", templateName, templateData)
			assert.NoError(t, err)
			assert.Contains(t, body, "alerts@example.com")
		})
	}
}

func TestInactiveUserDeletionFinalTemplateIncludesRecoveryLink(t *testing.T) {
	testutil.WithServerRoot(t)

	recoveryLink := "https://accounts.ente.com/recover-account#recoveryToken=test-token"
	body, err := getMailBodyWithBase("ente_base.html", "inactive-user-deletion/confirm_13m.html", map[string]interface{}{
		"Email":               "inactive@example.com",
		"DeletionDate":        "01 Apr 2026",
		"AccountRecoveryLink": recoveryLink,
	})

	assert.NoError(t, err)
	assert.Contains(t, body, recoveryLink)
	assert.Contains(t, body, "recover your account")
	assert.Contains(t, body, "within 7 days of deletion")
}
