package ente

import "testing"

func TestIsValidDomainWithoutScheme(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantErr bool
	}{
		{"simple domain", "google.com", false},
		{"multi-level domain", "sub.example.co.in", false},
		{"multi-level domain", "photos.ä.com", false},
		{"numeric in label", "a1b2c3.com", false},
		{"idn", "テスト.jp", false},
		{"long but valid label", "my-very-long-subdomain-name.example.com", false},

		{"leading space", " google.com", true},
		{"trailing space", "google.com ", true},
		{"both spaces", " google.com ", true},

		{"empty string", "", true},
		{"only spaces", "   ", true},

		{"http scheme", "http://google.com", true},
		{"https scheme", "https://example.com", true},
		{"ftp scheme", "ftp://example.com", true},

		{"underscore in label", "my_domain.com", true},
		{"invalid symbol", "exa$mple.com", true},
		{"space inside", "exa mple.com", true},

		{"missing dot", "localhost", true},
		{"ipv4 address", "172.17.0.2", true},
		{"ipv6 address", "2001:db8::1", true},
		{"single label TLD", "com", true},
		{"ends with dot", "example.com.", true},
		{"ends with dash", "example-.com", true},
		{"starts with dash", "-example.com", true},

		{"double dots", "example..com", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := isValidDomainWithoutScheme(tt.input)
			if (err != nil) != tt.wantErr {
				t.Errorf("isValidDomainWithoutScheme(%q) error = %v, wantErr %v", tt.input, err, tt.wantErr)
			}
		})
	}
}
