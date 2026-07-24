package email

import (
	"testing"

	"github.com/ente/museum/internal/testutil"
	"github.com/stretchr/testify/require"
)

func TestSpaceNotificationTemplateUsesEmailSafeLayout(t *testing.T) {
	testutil.WithServerRoot(t)

	body, err := getMailBody("space_notification.html", map[string]interface{}{
		"ActorLabel":        "@alice",
		"AppURL":            "https://ente.space/app",
		"IllustrationURL":   "https://email-assets.ente.com/space-new-post.png",
		"IllustrationWidth": 112,
		"Notification":      "just posted a new photo",
	})
	require.NoError(t, err)
	require.Contains(t, body, `<head>`)
	require.Contains(t, body, `role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" bgcolor="#f0f1f3"`)
	require.Contains(t, body, `bgcolor="#08C225"`)
	require.Contains(t, body, `style="background-color: #08C225; border-radius: 16px; color: #ffffff !important; display: block;`)
	require.Contains(t, body, "@alice")
	require.Contains(t, body, "just posted a new photo")
	require.Contains(t, body, `https://email-assets.ente.com/space-new-post.png`)
	require.Contains(t, body, `https://email-assets.ente.com/ente-2026-green.png`)
	require.Contains(t, body, `padding: 24px" title="Ente"`)
	require.Contains(t, body, `class="footer-icons" style="width: 24px; padding: 4px"`)
}

func TestSpaceDripTemplateRendersCTAAndBody(t *testing.T) {
	testutil.WithServerRoot(t)

	body, err := getMailBody("space_drip.html", map[string]interface{}{
		"BodyLines": []string{
			"Hey,",
			"Your Ente Space profile is still unfinished.",
		},
		"CTAURL":   "https://ente.space/app",
		"CTALabel": "Finish setup",
	})
	require.NoError(t, err)
	require.Contains(t, body, `role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" bgcolor="#f0f1f3"`)
	require.Contains(t, body, `max-width: 420px; width: 100%;`)
	require.Contains(t, body, `align="left" style="color: #5f5f5f;`)
	require.Contains(t, body, "Your Ente Space profile is still unfinished.")
	require.Contains(t, body, `style="border-collapse: separate; border-spacing: 0; width: 100%;"`)
	require.Contains(t, body, `href="https://ente.space/app"`)
	require.Contains(t, body, "Finish setup")
	require.Contains(t, body, `https://email-assets.ente.com/ente-2026-green.png`)
	require.Contains(t, body, `class="footer-icons" style="width: 24px; padding: 4px"`)
	require.Contains(t, body, "Ente Technologies, Inc.")
}

func TestSpaceDripTemplateOmitsCTAWithoutLabel(t *testing.T) {
	testutil.WithServerRoot(t)

	body, err := getMailBody("space_drip.html", map[string]interface{}{
		"BodyLines": []string{
			"Hey,",
			"Reply to this email or drop a message on our Discord!",
		},
		"CTAURL": "https://ente.space/app",
	})
	require.NoError(t, err)
	require.Contains(t, body, "Reply to this email or drop a message on our Discord!")
	require.Contains(t, body, `padding: 0 0 0; text-align: left;`)
	require.NotContains(t, body, `href="https://ente.space/app"`)
	require.NotContains(t, body, `Open Ente Space`)
	require.Contains(t, body, `https://email-assets.ente.com/ente-2026-green.png`)
}
