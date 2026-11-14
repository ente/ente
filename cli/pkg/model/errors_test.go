package model

import (
	"errors"
	"fmt"
	"net"
	"net/url"
	"testing"
)

func TestShouldRetrySync(t *testing.T) {
	dialErr := &net.OpError{Op: "dial", Net: "tcp", Err: errors.New("connect: connection refused")}
	readErr := &net.OpError{Op: "read", Net: "tcp", Err: errors.New("connection reset by peer")}
	tests := []struct {
		name string
		err  error
		want bool
	}{
		{
			name: "dial tcp connection error",
			err:  dialErr,
			want: true,
		},
		{
			name: "read tcp connection error inside a request error",
			err:  &url.Error{Op: "Get", URL: "https://api.example.com/files", Err: readErr},
			want: true,
		},
		{
			name: "read tcp connection error wrapped with %w",
			err:  fmt.Errorf("failed to get collections: %w", readErr),
			want: true,
		},
		{
			name: "API error text that mentions a dial tcp error is not retried",
			err:  errors.New("status 401 with err: dial tcp 203.0.113.7:443: connect: connection refused"),
			want: false,
		},
		{
			name: "API error text that mentions a GOAWAY is not retried",
			err:  errors.New("status 429 with err: http2: server sent GOAWAY and closed the connection"),
			want: false,
		},
		{
			name: "decryption error is not retried",
			err:  ErrDecryption,
			want: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := ShouldRetrySync(tt.err); got != tt.want {
				t.Errorf("ShouldRetrySync() = %v, want %v", got, tt.want)
			}
		})
	}
}
