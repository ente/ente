package crypto

import (
	b64 "encoding/base64"

	"github.com/ente/stacktrace"
)

var secretEncodings = []*b64.Encoding{
	b64.URLEncoding,
	b64.StdEncoding,
	b64.RawURLEncoding,
	b64.RawStdEncoding,
}

func DecodeSecret(secret string) ([]byte, error) {
	for _, encoding := range secretEncodings {
		if decoded, err := encoding.DecodeString(secret); err == nil {
			return decoded, nil
		}
	}
	return nil, stacktrace.NewError("secret is not valid base64 (standard or URL-safe, padded or unpadded)")
}
