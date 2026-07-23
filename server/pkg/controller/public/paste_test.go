package public

import (
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func testPasteContext(t *testing.T, headers map[string]string) *gin.Context {
	t.Helper()

	recorder := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(recorder)
	req := httptest.NewRequest("POST", "/paste/guard", nil)
	for key, value := range headers {
		req.Header.Set(key, value)
	}
	ctx.Request = req
	return ctx
}

func TestIsLikelyPreviewRequest_AllowsWhatsAppClientUA(t *testing.T) {
	ctx := testPasteContext(t, map[string]string{
		"User-Agent": "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/121.0.0.0 Mobile Safari/537.36 WhatsApp/2.24.2.10",
	})

	require.False(t, isLikelyPreviewRequest(ctx))
}

func TestIsLikelyPreviewRequest_BlocksWhatsAppBotUA(t *testing.T) {
	ctx := testPasteContext(t, map[string]string{
		"User-Agent": "WhatsAppBot/1.0",
	})

	require.True(t, isLikelyPreviewRequest(ctx))
}
