package ente

import (
	"crypto/md5"
	"encoding/base64"
	"strings"

	"github.com/ente/stacktrace"
)

const (
	MinMultipartPartSize = int64(5 << 20)
	MaxMultipartPartSize = int64(5 << 30)
)

func NormalizeMD5(value string) (string, error) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return "", stacktrace.Propagate(ErrBadRequest, "contentMD5 must not be empty")
	}
	decoded, err := base64.StdEncoding.DecodeString(trimmed)
	if err != nil {
		return "", stacktrace.Propagate(ErrBadRequest, "contentMD5 must be base64 encoded")
	}
	if len(decoded) != md5.Size {
		return "", stacktrace.Propagate(ErrBadRequest, "contentMD5 must be exactly 16 bytes")
	}
	return base64.StdEncoding.EncodeToString(decoded), nil
}

func ValidateMD5(value string) error {
	normalized, err := NormalizeMD5(value)
	if err != nil || normalized != value {
		return NewBadRequestWithMessage("MD5 checksums must be base64-encoded 16-byte digests")
	}
	return nil
}

func ValidateMultipartPartLength(contentLength, partLength int64) error {
	if partLength <= 0 || partLength > MaxMultipartPartSize {
		return NewBadRequestWithMessage("partLength must be between 1 byte and 5 GiB")
	}
	if contentLength > partLength && partLength < MinMultipartPartSize {
		return NewBadRequestWithMessage("partLength must be at least 5 MiB when more than one part is required")
	}
	return nil
}
