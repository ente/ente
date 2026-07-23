package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"
)

func TestAuthorizationResponseRequiresAccountsURLOnlyForPasskey(t *testing.T) {
	tests := []struct {
		name    string
		body    string
		wantErr bool
	}{
		{
			name: "plain login response may omit accounts URL",
			body: `{"id":1,"encryptedToken":"token"}`,
		},
		{
			name:    "passkey response requires accounts URL",
			body:    `{"id":1,"passkeySessionID":"passkey-session"}`,
			wantErr: true,
		},
		{
			name: "passkey response accepts museum accounts URL",
			body: `{"id":1,"passkeySessionID":"passkey-session","accountsUrl":"https://accounts.example.org"}`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var response AuthorizationResponse
			err := json.Unmarshal([]byte(tt.body), &response)
			if tt.wantErr {
				if err == nil {
					t.Fatal("expected missing accounts URL to be rejected")
				}
				if !strings.Contains(err.Error(), "accountsUrl is required") {
					t.Fatalf("unexpected error: %v", err)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}

func TestVerifySRPSessionRejectsPasskeyResponseWithoutAccountsURL(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/users/srp/verify-session" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"id":1,"passkeySessionID":"passkey-session"}`))
	}))
	defer server.Close()

	client := NewClient(Params{Host: server.URL})
	ctx := context.WithValue(t.Context(), "app", string(AppPhotos))

	_, err := client.VerifySRPSession(ctx, uuid.New(), uuid.New(), "client-m1")
	if err == nil {
		t.Fatal("expected response parsing to reject missing accounts URL")
	}
	if !strings.Contains(err.Error(), "accountsUrl is required") {
		t.Fatalf("unexpected error: %v", err)
	}
}
