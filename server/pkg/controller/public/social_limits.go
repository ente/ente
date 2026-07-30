package public

import (
	"encoding/base64"

	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
)

const (
	secretBoxOverheadBytes = 16
	maxCommentBytes        = 280
	maxAnonNameBytes       = 50
)

func validateEncryptedPayloadLength(cipher string, maxBytes int, tooLongErr error) error {
	data, err := base64.StdEncoding.DecodeString(cipher)
	if err != nil {
		return stacktrace.Propagate(ente.ErrBadRequest, "invalid cipher encoding")
	}
	if len(data) < secretBoxOverheadBytes {
		return stacktrace.Propagate(ente.ErrBadRequest, "cipher too short")
	}
	if len(data)-secretBoxOverheadBytes > maxBytes {
		return tooLongErr
	}
	return nil
}
