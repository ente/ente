package listmonk

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestGetSubscriberIDReturnsStatusError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte("auth failed"))
	}))
	defer server.Close()

	_, err := GetSubscriberID(server.URL, "user", "pass", "missing@example.com")
	if err == nil {
		t.Fatal("expected error")
	}
	if errors.Is(err, ErrSubscriberNotFound) {
		t.Fatal("status failure was reported as subscriber not found")
	}
	if !strings.Contains(err.Error(), "status 401") {
		t.Fatalf("err = %v, want status 401", err)
	}
}
