package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/testutil"
)

func TestRecordRateLimitRejection(t *testing.T) {
	counter := rateLimitRejections.WithLabelValues(
		string(rateLimitScopeIP),
		http.MethodGet,
		"/test/rate-limit",
	)
	before := testutil.ToFloat64(counter)

	recordRateLimitRejection(rateLimitScopeIP, http.MethodGet, "/test/rate-limit")

	after := testutil.ToFloat64(counter)
	if after != before+1 {
		t.Fatalf("rate limit rejection counter = %v, want %v", after, before+1)
	}
}

func TestRateLimitScopeLabels(t *testing.T) {
	tests := []struct {
		scope rateLimitScope
		want  string
	}{
		{scope: rateLimitScopeIP, want: "ip"},
		{scope: rateLimitScopeCollection, want: "collection"},
		{scope: rateLimitScopeUser, want: "user"},
		{scope: rateLimitScopeRouteGlobal, want: "route_global"},
		{scope: rateLimitScopeProcessGlobal, want: "process_global"},
	}

	for _, tt := range tests {
		if got := string(tt.scope); got != tt.want {
			t.Errorf("rate limit scope label = %q, want %q", got, tt.want)
		}
	}
}

func TestGetRateLimitKeyReturnsScopeForSelectedKey(t *testing.T) {
	gin.SetMode(gin.TestMode)
	rateLimiter := &RateLimitMiddleware{}
	check := func(path string, publicContext any, wantKey string, wantScope rateLimitScope) {
		t.Helper()
		context, _ := gin.CreateTestContext(httptest.NewRecorder())
		context.Request = httptest.NewRequest(http.MethodPost, path, nil)
		context.Request.RemoteAddr = "198.51.100.1:1234"
		if publicContext != nil {
			context.Set(auth.PublicAccessKey, publicContext)
		}
		gotKey, gotScope := rateLimiter.getRateLimitKey(context, path)
		if gotKey != wantKey || gotScope != wantScope {
			t.Errorf("getRateLimitKey(%q) = (%q, %q), want (%q, %q)", path, gotKey, gotScope, wantKey, wantScope)
		}
	}

	check("/users/srp/attributes", nil, "198.51.100.1-/users/srp/attributes", rateLimitScopeIP)
	check("/public-collection/upload-url", ente.PublicAccessContext{CollectionID: 42}, "collection:42-/public-collection/upload-url", rateLimitScopeCollection)
	check("/public-collection/upload-url", nil, "198.51.100.1-/public-collection/upload-url", rateLimitScopeIP)
}
