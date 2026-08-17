package cast

import (
	"encoding/base64"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ente/museum/ente"
	entity "github.com/ente/museum/ente/cast"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestValidatePQPublicKey(t *testing.T) {
	valid := base64.StdEncoding.EncodeToString(make([]byte, pqPublicKeyBytes))
	invalidBase64 := strings.Repeat("!", len(valid))
	wrongLength := base64.StdEncoding.EncodeToString(make([]byte, pqPublicKeyBytes-1))

	for name, key := range map[string]*string{
		"omitted":        nil,
		"valid":          &valid,
		"invalid base64": &invalidBase64,
		"wrong length":   &wrongLength,
	} {
		t.Run(name, func(t *testing.T) {
			err := validatePQPublicKey(key)
			if (name == "omitted" || name == "valid") != (err == nil) {
				t.Fatalf("validatePQPublicKey() error = %v", err)
			}
			if err != nil && !errors.Is(err, ente.ErrBadRequest) {
				t.Fatalf("validatePQPublicKey() error = %v, want bad request", err)
			}
		})
	}
}

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
