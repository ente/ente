package api

import (
	"encoding/json"
	"strings"
	"testing"
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
