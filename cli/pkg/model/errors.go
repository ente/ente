package model

import (
	"errors"
	"net"
	"strings"
)

var ErrDecryption = errors.New("error while decrypting the file")
var ErrLiveZip = errors.New("error: no image or video file found in zip")

// ShouldRetrySync reports whether a failed sync should be retried from the start.
// It matches the error type (a TCP dial or read failure), not its text, so an API
// error whose body mentions a network error is not retried. A server GOAWAY is not
// matched here: the download client retries it (internal/api/client.go).
func ShouldRetrySync(err error) bool {
	var opErr *net.OpError
	return errors.As(err, &opErr) && opErr.Net == "tcp" && (opErr.Op == "read" || opErr.Op == "dial")
}

func IsBadTimeStampError(err error) bool {
	return strings.Contains(err.Error(), "year outside of range ")
}
