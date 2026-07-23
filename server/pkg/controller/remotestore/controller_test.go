package remotestore

import "testing"

func TestIsReservedCustomDomain(t *testing.T) {
	tests := []struct {
		name            string
		value           string
		configuredCNAME string
		want            bool
	}{
		{"configured cname", "custom-domain.example.com", "custom-domain.example.com", true},
		{"configured cname case insensitive", "CUSTOM-DOMAIN.EXAMPLE.COM", "custom-domain.example.com", true},
		{"current ente cname", "my.ente.com", "custom-domain.example.com", true},
		{"legacy ente cname", "my.ente.io", "custom-domain.example.com", true},
		{"user domain", "albums.example.com", "custom-domain.example.com", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isReservedCustomDomain(tt.value, tt.configuredCNAME)
			if got != tt.want {
				t.Fatalf("isReservedCustomDomain(%q, %q) = %v, want %v", tt.value, tt.configuredCNAME, got, tt.want)
			}
		})
	}
}
