package email

import (
	"testing"

	"github.com/ente/museum/internal/testutil"
	"github.com/stretchr/testify/require"
)

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
	require.Contains(t, body, "Your Ente Space profile is still unfinished.")
	require.Contains(t, body, `href="https://ente.space/app"`)
	require.Contains(t, body, "Finish setup")
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
	require.NotContains(t, body, `href="https://ente.space/app"`)
	require.NotContains(t, body, `Open Ente Space`)
}
