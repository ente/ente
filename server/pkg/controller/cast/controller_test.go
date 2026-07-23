package cast

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ente/museum/ente"
	entity "github.com/ente/museum/ente/cast"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestRegisterDeviceRejectsOversizedUserAgent(t *testing.T) {
	gin.SetMode(gin.TestMode)

	recorder := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(recorder)
	ctx.Request = httptest.NewRequest(http.MethodPost, "/cast/device-info", nil)
	ctx.Request.Header.Set("User-Agent", strings.Repeat("a", maxRegisterDeviceUserAgentBytes+1))

	controller := &Controller{}

	code, err := controller.RegisterDevice(ctx, &entity.RegisterDeviceRequest{
		PublicKey: "public-key",
	})

	require.Empty(t, code)
	require.Error(t, err)
	apiErr, ok := err.(*ente.ApiError)
	require.True(t, ok)
	require.Equal(t, ente.InternalError, apiErr.Code)
	require.Equal(t, http.StatusInternalServerError, apiErr.HttpStatusCode)
}
