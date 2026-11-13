package ente

import (
	"crypto/md5"
	"encoding/base64"
	"strings"
	"time"

	"github.com/ente/stacktrace"
)

const (
	MinMultipartPartSize   = int64(5 << 20)
	MaxMultipartPartSize   = int64(5 << 30)
	MinMultipartUploadSize = int64(16 << 20)
)

const (
	tinyUploadMaxSize      = int64(1 << 10)
	smallUploadMaxSize     = int64(100 << 10)
	mediumMultipartMaxSize = int64(100 << 20)

	tinyUploadURLValidity            = 5 * time.Minute
	smallUploadURLValidity           = 15 * time.Minute
	defaultUploadURLValidity         = 24 * time.Hour
	mediumMultipartUploadURLValidity = 24 * time.Hour
	multipartUploadURLValidity       = 7 * 24 * time.Hour
)

func UploadURLValidity(contentLength *int64) time.Duration {
	if contentLength == nil {
		return defaultUploadURLValidity
	}
	switch {
	case *contentLength < tinyUploadMaxSize:
		return tinyUploadURLValidity
	case *contentLength < smallUploadMaxSize:
		return smallUploadURLValidity
	default:
		return defaultUploadURLValidity
	}
}

func MultipartUploadURLValidity(contentLength *int64) time.Duration {
	if contentLength != nil && *contentLength <= mediumMultipartMaxSize {
		return mediumMultipartUploadURLValidity
	}
	return multipartUploadURLValidity
}

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
	if contentLength < MinMultipartUploadSize {
		return NewBadRequestWithMessage("multipart uploads require a contentLength of at least 16 MiB")
	}
	if partLength <= 0 || partLength > MaxMultipartPartSize {
		return NewBadRequestWithMessage("partLength must be between 1 byte and 5 GiB")
	}
	if contentLength > partLength && partLength < MinMultipartPartSize {
		return NewBadRequestWithMessage("partLength must be at least 5 MiB when more than one part is required")
	}
	return nil
}
