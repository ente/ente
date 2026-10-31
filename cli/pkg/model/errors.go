package model

import (
	"errors"
	"strings"
)

var ErrDecryption = errors.New("error while decrypting the file")
var ErrLiveZip = errors.New("error: no image or video file found in zip")

// ShouldRetrySync reports whether a failed sync should be retried from the start.
// Go's HTTP/2 client reports a server GOAWAY as "server sent GOAWAY and closed the
// connection" (net/http/internal/http2/transport.go:1959 in Go 1.27.3). Files that
// already synced are skipped on the next run (remote_to_disk_file.go:49).
func ShouldRetrySync(err error) bool {
	return strings.Contains(err.Error(), "read tcp") ||
		strings.Contains(err.Error(), "dial tcp") ||
		strings.Contains(err.Error(), "server sent GOAWAY")
}

func IsBadTimeStampError(err error) bool {
	return strings.Contains(err.Error(), "year outside of range ")
}
