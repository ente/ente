package main

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/viper"
)

func TestCORS(t *testing.T) {
	gin.SetMode(gin.TestMode)
	tests := []struct {
		name       string
		method     string
		path       string
		origin     string
		host       string
		wantStatus int
		wantHandle bool
		wantWarn   bool
		enforce    bool
	}{
		{"configured origin", http.MethodGet, "/users/details", "https://photos.ente.com", "api.ente.com", http.StatusNoContent, true, false, false},
		{"unknown origin", http.MethodGet, "/users/details", "https://unknown.example", "api.ente.com", http.StatusNoContent, true, true, false},
		{"malformed origin", http.MethodGet, "/users/details", "%", "api.ente.com", http.StatusNoContent, true, true, false},
		{"native client", http.MethodGet, "/users/details", "", "api.ente.com", http.StatusNoContent, true, false, false},
		{"unconfigured same host", http.MethodPost, "/users/ott", "https://ente.example", "ente.example", http.StatusNoContent, true, true, false},
		{"desktop app", http.MethodGet, "/users/details", "ente://app", "api.ente.com", http.StatusNoContent, true, false, false},
		{"localhost", http.MethodGet, "/users/details", "http://localhost:3000", "api.ente.com", http.StatusNoContent, true, false, false},
		{"localhost subdomain", http.MethodGet, "/users/details", "https://photos.localhost:3000", "api.ente.com", http.StatusNoContent, true, false, false},
		{"IPv4 loopback", http.MethodGet, "/users/details", "http://127.1.2.3:3000", "api.ente.com", http.StatusNoContent, true, false, false},
		{"IPv6 loopback", http.MethodGet, "/users/details", "http://[::1]:3000", "api.ente.com", http.StatusNoContent, true, false, false},
		{"opaque origin", http.MethodGet, "/users/details", "null", "api.ente.com", http.StatusNoContent, true, true, false},
		{"private address", http.MethodGet, "/users/details", "http://192.168.1.2:3000", "api.ente.com", http.StatusNoContent, true, true, false},
		{"localhost lookalike", http.MethodGet, "/users/details", "http://localhost.example:3000", "api.ente.com", http.StatusNoContent, true, true, false},
		{"non-HTTP loopback", http.MethodGet, "/users/details", "ftp://localhost", "api.ente.com", http.StatusNoContent, true, true, false},
		{"public file count", http.MethodGet, "/files/count", "null", "api.ente.com", http.StatusNoContent, true, false, true},
		{"public billing plans", http.MethodGet, "/billing/plans/v2", "https://unknown.example", "api.ente.com", http.StatusNoContent, true, false, true},
		{"custom album domain", http.MethodGet, "/public-collection/info", "https://gallery.example", "api.ente.com", http.StatusNoContent, true, false, false},
		{"album prefix lookalike", http.MethodGet, "/public-collection-evil", "https://gallery.example", "api.ente.com", http.StatusNoContent, true, true, false},
		{"unknown preflight", http.MethodOptions, "/users/details", "https://unknown.example", "api.ente.com", http.StatusOK, false, false, false},
		{"enforced configured origin", http.MethodGet, "/users/details", "https://photos.ente.com", "api.ente.com", http.StatusNoContent, true, false, true},
		{"enforced unknown origin", http.MethodGet, "/users/details", "https://unknown.example", "api.ente.com", http.StatusForbidden, false, true, true},
		{"enforced unknown preflight", http.MethodOptions, "/users/details", "https://unknown.example", "api.ente.com", http.StatusForbidden, false, true, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var logs bytes.Buffer
			logger := log.StandardLogger()
			oldOutput := logger.Out
			logger.SetOutput(&logs)
			t.Cleanup(func() { logger.SetOutput(oldOutput) })

			handled := false
			server := gin.New()
			server.Use(corsForOrigins([]string{"https://photos.ente.com", "ente://app"}, tt.enforce))
			handler := func(c *gin.Context) {
				handled = true
				c.Status(http.StatusNoContent)
			}
			server.GET("/*path", handler)
			server.POST("/*path", handler)

			req := httptest.NewRequest(tt.method, tt.path, nil)
			req.Host = tt.host
			if tt.origin != "" {
				req.Header.Set("Origin", tt.origin)
			}
			resp := httptest.NewRecorder()
			server.ServeHTTP(resp, req)

			if resp.Code != tt.wantStatus {
				t.Errorf("status = %d, want %d", resp.Code, tt.wantStatus)
			}
			wantOrigin := tt.origin
			if tt.wantStatus == http.StatusForbidden {
				wantOrigin = ""
			}
			if got := resp.Header().Get("Access-Control-Allow-Origin"); got != wantOrigin {
				t.Errorf("allowed origin = %q, want %q", got, wantOrigin)
			}
			if handled != tt.wantHandle {
				t.Errorf("handler called = %t, want %t", handled, tt.wantHandle)
			}
			if got := strings.Contains(logs.String(), "unknown CORS origin"); got != tt.wantWarn {
				t.Errorf("warning logged = %t, want %t; log: %s", got, tt.wantWarn, logs.String())
			}
		})
	}
}

func TestCORSProductionOriginsAreDefaults(t *testing.T) {
	viper.Reset()
	viper.Set("apps", map[string]interface{}{"accounts": "https://accounts.ente.com"})
	setAppDefaults()
	t.Cleanup(viper.Reset)

	var logs bytes.Buffer
	logger := log.StandardLogger()
	oldOutput := logger.Out
	logger.SetOutput(&logs)
	t.Cleanup(func() { logger.SetOutput(oldOutput) })

	server := gin.New()
	server.Use(cors())
	server.GET("/ping", func(c *gin.Context) { c.Status(http.StatusNoContent) })

	origins := []string{
		"https://photos.ente.com",
		"https://albums.ente.com",
		"https://embed.ente.com",
		"https://ente.com",
		"https://ente.io",
		"https://web.ente.io",
		"https://auth.ente.io",
		"https://locker.ente.io",
		"https://share.ente.io",
		"https://payments.ente.io",
		"https://embed.ente.io",
		"https://cast.ente.io",
		"https://staff.ente.sh",
		"https://auth.ente.com",
		"https://locker.ente.com",
		"https://share.ente.com",
		"https://paste.ente.com",
		"https://memories.ente.com",
		"https://accounts.ente.com",
		"https://accounts.ente.io",
		"https://payments.ente.com",
		"https://cast.ente.com",
		"https://family.ente.io",
		"https://ente.space",
		"https://legacy.ente.com",
		"ente://app",
	}
	for _, origin := range origins {
		req := httptest.NewRequest(http.MethodGet, "/ping", nil)
		req.Header.Set("Origin", origin)
		resp := httptest.NewRecorder()
		server.ServeHTTP(resp, req)
		if resp.Code != http.StatusNoContent {
			t.Errorf("origin %q: status = %d, want %d", origin, resp.Code, http.StatusNoContent)
		}
	}
	if logs.Len() != 0 {
		t.Errorf("production origins logged warnings: %s", logs.String())
	}
}

func TestCORSReportOnlyDefault(t *testing.T) {
	tests := []struct {
		name       string
		values     map[string]interface{}
		reportOnly bool
	}{
		{"legacy configuration", nil, true},
		{"blank web apps", map[string]interface{}{"apps.photos": "", "apps.auth": "", "apps.locker": ""}, true},
		{"photos configured", map[string]interface{}{"apps.photos": "https://photos.example"}, false},
		{"auth configured", map[string]interface{}{"apps.auth": "https://auth.example"}, false},
		{"locker configured", map[string]interface{}{"apps.locker": "https://locker.example"}, false},
		{"extra origin configured", map[string]interface{}{"apps.extra-origins": []string{"https://extra.example"}}, false},
		{"explicit report-only", map[string]interface{}{"apps.photos": "https://photos.example", "apps.cors-report-only": true}, true},
		{"explicit enforcement", map[string]interface{}{"apps.cors-report-only": false}, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			viper.Reset()
			t.Cleanup(viper.Reset)
			for key, value := range tt.values {
				viper.Set(key, value)
			}
			setAppDefaults()
			if got := viper.GetBool("apps.cors-report-only"); got != tt.reportOnly {
				t.Errorf("report-only = %t, want %t", got, tt.reportOnly)
			}
		})
	}
}

func TestCORSUsesConfiguredAppOrigins(t *testing.T) {
	viper.Reset()
	viper.Set("apps.photos", "https://photos.example/app")
	viper.Set("apps.extra-origins", []string{"https://extra.example"})
	t.Cleanup(viper.Reset)

	var logs bytes.Buffer
	logger := log.StandardLogger()
	oldOutput := logger.Out
	logger.SetOutput(&logs)
	t.Cleanup(func() { logger.SetOutput(oldOutput) })

	server := gin.New()
	server.Use(cors())
	server.GET("/ping", func(c *gin.Context) { c.Status(http.StatusNoContent) })
	for _, origin := range []string{"https://photos.example", "https://extra.example"} {
		req := httptest.NewRequest(http.MethodGet, "/ping", nil)
		req.Header.Set("Origin", origin)
		server.ServeHTTP(httptest.NewRecorder(), req)
	}

	if logs.Len() != 0 {
		t.Errorf("configured app origin logged a warning: %s", logs.String())
	}
}
