package api

import (
	"bytes"
	"testing"
)

func TestValidateAuthToken(t *testing.T) {
	for _, endpoint := range []struct {
		origin string
		strict bool
	}{
		{"https://api.ente.com", true},
		{"https://api.ente.in:443/prefix", true},
		{"http://localhost:8080", true},
		{"https://API.ENTE.COM", true},
		{"https://self-hosted.example", false},
		{"http://127.0.0.1:8080", false},
		{"https://api.ente.com.example", false},
		{"https://api.ente.com@example.org", false},
	} {
		client := NewClient(Params{Host: endpoint.origin})
		for _, test := range []struct {
			token  []byte
			tagged bool
		}{
			{append([]byte("auth-token"), bytes.Repeat([]byte{1}, 32)...), true},
			{bytes.Repeat([]byte{1}, 32), false},
			{append([]byte("auth-token"), bytes.Repeat([]byte{1}, 31)...), false},
			{append([]byte("auth-token"), bytes.Repeat([]byte{1}, 33)...), false},
			{[]byte("delete-jwtheader.payload.signature"), false},
		} {
			if (client.ValidateAuthToken(test.token) == nil) != (!endpoint.strict || test.tagged) {
				t.Errorf("unexpected validation result for %s, length %d", endpoint.origin, len(test.token))
			}
		}
	}
}
