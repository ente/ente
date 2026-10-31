package model

import (
	"errors"
	"fmt"
	"testing"
)

func TestShouldRetrySync(t *testing.T) {
	tests := []struct {
		name string
		err  error
		want bool
	}{
		{
			name: "HTTP/2 GOAWAY from the server while downloading a file",
			err:  fmt.Errorf("error downloading file 834231964: http2: server sent GOAWAY and closed the connection; LastStreamID=19999, ErrCode=NO_ERROR, debug=\"\""),
			want: true,
		},
		{
			name: "read tcp connection error",
			err:  errors.New("read tcp 10.0.0.2:51234->203.0.113.7:443: connection reset by peer"),
			want: true,
		},
		{
			name: "dial tcp connection error",
			err:  errors.New("dial tcp 203.0.113.7:443: connect: connection refused"),
			want: true,
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
