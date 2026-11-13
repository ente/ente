package middleware

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"testing/iotest"

	"github.com/gin-gonic/gin"
	"github.com/sirupsen/logrus"
	logtest "github.com/sirupsen/logrus/hooks/test"
	"github.com/stretchr/testify/require"
)

func TestLimitRequestBody(t *testing.T) {
	gin.SetMode(gin.TestMode)
	logger := logrus.StandardLogger()
	originalOutput := logger.Out
	logger.SetOutput(io.Discard)
	t.Cleanup(func() { logger.SetOutput(originalOutput) })

	for _, tc := range []struct {
		name string
		size int
	}{
		{"empty", 0},
		{"below limit", maxRequestBodySize - 1},
		{"at limit", maxRequestBodySize},
		{"above limit", maxRequestBodySize + 1},
	} {
		body := strings.Repeat("a", tc.size)
		for _, framing := range []string{"known length", "unknown length"} {
			t.Run(tc.name+"/"+framing, func(t *testing.T) {
				for _, path := range []string{"/test", "/events"} {
					t.Run(path, func(t *testing.T) {
						rateLimiter := &RateLimitMiddleware{limit: 1}
						router := gin.New()
						router.Use(rateLimiter.GlobalRateLimiter(), LimitRequestBody(), Logger(func(c *gin.Context) string { return c.FullPath() }))
						called := false
						router.POST(path, func(c *gin.Context) {
							called = true
							got, err := io.ReadAll(c.Request.Body)
							require.NoError(t, err)
							require.True(t, string(got) == body, "accepted request body changed")
							c.Status(http.StatusNoContent)
						})
						reader := strings.NewReader(body)
						req := httptest.NewRequest(http.MethodPost, path, reader)
						if framing == "unknown length" {
							req.ContentLength = -1
							req.TransferEncoding = []string{"chunked"}
						}
						response := httptest.NewRecorder()
						router.ServeHTTP(response, req)
						require.Equal(t, int64(1), rateLimiter.count)

						if tc.size > maxRequestBodySize {
							require.Equal(t, http.StatusRequestEntityTooLarge, response.Code)
							require.False(t, called)
							if framing == "known length" {
								require.Equal(t, tc.size, reader.Len(), "oversized declared body was read")
							}
						} else {
							require.Equal(t, http.StatusNoContent, response.Code)
							require.True(t, called)
						}
					})
				}
			})
		}
	}
}

func TestGlobalRateLimitBeforeBodyRead(t *testing.T) {
	gin.SetMode(gin.TestMode)
	for _, tc := range []struct {
		name          string
		method        string
		path          string
		contentLength int64
	}{
		{"declared oversized body", http.MethodPost, "/test", maxRequestBodySize + 1},
		{"unknown length body", http.MethodPost, "/test", -1},
		{"unmatched route", http.MethodPost, "/missing", 4},
		{"options", http.MethodOptions, "/test", 4},
	} {
		t.Run(tc.name, func(t *testing.T) {
			rateLimiter := &RateLimitMiddleware{limit: 0}
			router := gin.New()
			router.Use(rateLimiter.GlobalRateLimiter(), LimitRequestBody(), Logger(func(c *gin.Context) string { return c.FullPath() }))
			router.POST("/test", func(c *gin.Context) {
				t.Fatal("handler called after rate limit rejection")
			})
			body := strings.NewReader("body")
			req := httptest.NewRequest(tc.method, tc.path, body)
			req.ContentLength = tc.contentLength
			response := httptest.NewRecorder()
			router.ServeHTTP(response, req)

			require.Equal(t, http.StatusTooManyRequests, response.Code)
			require.JSONEq(t, `{"error":"Rate limit breached, try later"}`, response.Body.String())
			require.Equal(t, int64(1), rateLimiter.count)
			require.Equal(t, 4, body.Len(), "rate-limited body was read")
		})
	}
}

func TestLoggerStopsOnBodyReadError(t *testing.T) {
	gin.SetMode(gin.TestMode)
	logger := logrus.StandardLogger()
	originalHooks := logger.ReplaceHooks(make(logrus.LevelHooks))
	t.Cleanup(func() { logger.ReplaceHooks(originalHooks) })
	hook := logtest.NewGlobal()

	rateLimiter := &RateLimitMiddleware{limit: 1}
	router := gin.New()
	router.Use(rateLimiter.GlobalRateLimiter(), LimitRequestBody(), Logger(func(c *gin.Context) string { return c.FullPath() }))
	router.POST("/test", func(c *gin.Context) {
		t.Fatal("handler called after body read error")
	})
	body := io.MultiReader(strings.NewReader("partial-body"), iotest.ErrReader(io.ErrUnexpectedEOF))
	req := httptest.NewRequest(http.MethodPost, "/test", body)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, req)

	require.Equal(t, int64(1), rateLimiter.count)
	require.Equal(t, http.StatusBadRequest, response.Code)
	entries := hook.AllEntries()
	require.Len(t, entries, 1)
	require.Equal(t, "Request failed", entries[0].Message)
	require.NotContains(t, entries[0].Data, "req_body")
}
