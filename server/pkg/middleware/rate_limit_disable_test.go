package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/ente/museum/pkg/controller/discord"
	"github.com/gin-gonic/gin"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

func TestRateLimitDisabledOnlyInLocalEnvironment(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name           string
		environment    string
		disableSetting bool
		wantDisabled   bool
	}{
		{
			name:           "local_unset_disabled_true",
			environment:    "",
			disableSetting: true,
			wantDisabled:   true,
		},
		{
			name:           "local_explicit_disabled_true",
			environment:    "local",
			disableSetting: true,
			wantDisabled:   true,
		},
		{
			name:           "production_disabled_true_ignored",
			environment:    "production",
			disableSetting: true,
			wantDisabled:   false,
		},
		{
			name:           "local_disabled_false_enforced",
			environment:    "local",
			disableSetting: false,
			wantDisabled:   false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("ENVIRONMENT", tc.environment)
			viper.Set("internal.disable-rate-limit", tc.disableSetting)
			t.Cleanup(func() {
				viper.Set("internal.disable-rate-limit", false)
			})

			rl := NewRateLimitMiddleware(discord.NewDiscordController(nil, "test", "test"), 1, 1, time.Hour)
			t.Cleanup(rl.Stop)

			apiRouter := gin.New()
			apiRouter.Use(rl.APIRateLimitMiddleware(func(c *gin.Context) string {
				return c.FullPath()
			}))
			apiRouter.POST("/users/ott", func(c *gin.Context) {
				c.Status(http.StatusNoContent)
			})

			sendOTT := func() int {
				req := httptest.NewRequest(http.MethodPost, "/users/ott", nil)
				req.RemoteAddr = "127.0.0.1:12345"
				res := httptest.NewRecorder()
				apiRouter.ServeHTTP(res, req)
				return res.Code
			}

			globalRouter := newGlobalRateLimitTestRouter(rl)

			if tc.wantDisabled {
				for range 15 {
					require.Equal(t, http.StatusNoContent, sendOTT())
				}
				for range 5 {
					require.Equal(t, http.StatusNoContent, globalRateLimitTestRequest(globalRouter, http.MethodGet, "/collections"))
				}
				return
			}

			for range 10 {
				require.Equal(t, http.StatusNoContent, sendOTT())
			}
			require.Equal(t, http.StatusTooManyRequests, sendOTT())

			require.Equal(t, http.StatusNoContent, globalRateLimitTestRequest(globalRouter, http.MethodGet, "/collections"))
			require.Equal(t, http.StatusTooManyRequests, globalRateLimitTestRequest(globalRouter, http.MethodGet, "/collections"))
		})
	}
}
