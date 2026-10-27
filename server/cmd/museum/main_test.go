package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/ente/museum/pkg/controller/discord"
	"github.com/ente/museum/pkg/middleware"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestURLSanitizer(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	var before, after string
	router.Use(func(c *gin.Context) {
		before = urlSanitizer(c)
		c.Next()
		after = urlSanitizer(c)
	}, cors())
	for _, route := range []string{"/public-collection/info", "/public-collection/diff", "/file-link/info", "/files/download/:fileID"} {
		router.GET(route, func(c *gin.Context) { c.Status(http.StatusNoContent) })
	}
	for _, route := range []string{"/cast/device-info", "/cast/device-info/"} {
		router.POST(route, func(c *gin.Context) { c.Status(http.StatusNoContent) })
	}

	for _, tc := range []struct {
		method   string
		target   string
		path     string
		status   int
		location string
	}{
		{http.MethodGet, "/public-collection/info", "/public-collection/info", http.StatusNoContent, ""},
		{http.MethodGet, "/public-collection/%69nfo?sinceTime=1", "/public-collection/info", http.StatusNoContent, ""},
		{http.MethodGet, "/public-collection/info?", "/public-collection/info", http.StatusNoContent, ""},
		{http.MethodGet, "/public-collection/d%69ff", "/public-collection/diff", http.StatusNoContent, ""},
		{http.MethodGet, "/file-link/%69nfo", "/file-link/info", http.StatusNoContent, ""},
		{http.MethodGet, "/files/download/%31", "/files/download/:fileID", http.StatusNoContent, ""},
		{http.MethodGet, "/files/download/files", "/files/download/:fileID", http.StatusNoContent, ""},
		{http.MethodPost, "/cast/device-info", "/cast/device-info", http.StatusNoContent, ""},
		{http.MethodPost, "/cast/device-%69nfo/", "/cast/device-info/", http.StatusNoContent, ""},
		{http.MethodGet, "/public-collection/info/", "", http.StatusMovedPermanently, "/public-collection/info"},
		{http.MethodPost, "/cast/device-info//", "", http.StatusTemporaryRedirect, "/cast/device-info/"},
		{http.MethodGet, "/public-collection/info//", "/unknown-api", http.StatusNotFound, ""},
		{http.MethodGet, "/public-collection/%2569nfo", "/unknown-api", http.StatusNotFound, ""},
		{http.MethodPost, "/public-collection/info", "/unknown-api", http.StatusNotFound, ""},
		{http.MethodGet, "/missing", "/unknown-api", http.StatusNotFound, ""},
		{http.MethodOptions, "/public-collection/info", "/options", http.StatusOK, ""},
	} {
		t.Run(tc.method+" "+tc.target, func(t *testing.T) {
			before, after = "", ""
			response := httptest.NewRecorder()
			router.ServeHTTP(response, httptest.NewRequest(tc.method, tc.target, nil))
			require.Equal(t, tc.status, response.Code)
			require.Equal(t, tc.location, response.Header().Get("Location"))
			require.Equal(t, tc.path, before)
			require.Equal(t, tc.path, after)
		})
	}
}

func TestURLSanitizerSharesRateLimitsAcrossEncodings(t *testing.T) {
	gin.SetMode(gin.TestMode)
	for _, paths := range [][]string{
		{"/public-collection/verify-password", "/public-collection/verify-%70assword", "/public-collection%2Fverify-password"},
		{"/file-link/verify-password", "/file-link/verify-%70assword", "/file-link%2Fverify-password"},
	} {
		t.Run(paths[0], func(t *testing.T) {
			rateLimiter := middleware.NewRateLimitMiddleware(discord.NewDiscordController(nil, "test", "test"), 1000, 1000, time.Minute)
			t.Cleanup(rateLimiter.Stop)
			router := gin.New()
			router.POST(paths[0], rateLimiter.APIRateLimitMiddleware(urlSanitizer), func(c *gin.Context) {
				c.Status(http.StatusNoContent)
			})
			for i := range 13 {
				path := paths[i%len(paths)]
				request := httptest.NewRequest(http.MethodPost, path, nil)
				request.RemoteAddr = "192.0.2.1:1234"
				response := httptest.NewRecorder()
				router.ServeHTTP(response, request)
				wantStatus := http.StatusNoContent
				if i >= 10 {
					wantStatus = http.StatusTooManyRequests
				}
				require.Equal(t, wantStatus, response.Code, "request %d to %s", i+1, path)
			}
		})
	}
}
