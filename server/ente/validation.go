package ente

import "encoding/base64"

func ValidateBase64Length(value string, size int) error {
	if len(value) != base64.StdEncoding.EncodedLen(size) {
		return NewBadRequestWithMessage("invalid length")
	}
	decoded, err := base64.StdEncoding.Strict().DecodeString(value)
	if err != nil {
		return NewBadRequestWithMessage("invalid base64")
	}
	if len(decoded) != size {
		return NewBadRequestWithMessage("invalid length")
	}
	return nil
}
