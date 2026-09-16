package crypto

import (
	"encoding/base64"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

var testSecretRaw = []byte{
	0xfb, 0xef, 0xbe, 0x03, 0x28, 0x8f, 0x6a, 0x9e,
	0x6a, 0xfa, 0x6d, 0x61, 0x87, 0x9b, 0x42, 0x82,
	0x79, 0x64, 0x74, 0x46, 0x91, 0xcd, 0xd8, 0x27,
	0x1c, 0x72, 0xcb, 0xac, 0xf4, 0xfa, 0x3e, 0x87,
}

func TestDecodeSecret(t *testing.T) {
	t.Run("standard_base64", func(t *testing.T) {
		encoded := base64.StdEncoding.EncodeToString(testSecretRaw)
		require.True(t, strings.ContainsAny(encoded, "+/"))
		decoded, err := DecodeSecret(encoded)
		require.NoError(t, err)
		require.Equal(t, testSecretRaw, decoded)
	})

	t.Run("url_safe_base64", func(t *testing.T) {
		encoded := base64.URLEncoding.EncodeToString(testSecretRaw)
		require.True(t, strings.ContainsAny(encoded, "-_"))
		decoded, err := DecodeSecret(encoded)
		require.NoError(t, err)
		require.Equal(t, testSecretRaw, decoded)
	})

	t.Run("unpadded_variants", func(t *testing.T) {
		for _, encoded := range []string{
			base64.RawStdEncoding.EncodeToString(testSecretRaw),
			base64.RawURLEncoding.EncodeToString(testSecretRaw),
		} {
			decoded, err := DecodeSecret(encoded)
			require.NoError(t, err, encoded)
			require.Equal(t, testSecretRaw, decoded)
		}
	})

	t.Run("default_jwt_secret_still_decodes", func(t *testing.T) {
		decoded, err := DecodeSecret("i2DecQmfGreG6q1vBj5tCokhlN41gcfS2cjOs9Po-u8=")
		require.NoError(t, err)
		require.Len(t, decoded, 32)
	})

	t.Run("invalid_secret", func(t *testing.T) {
		_, err := DecodeSecret("not valid base64!!!")
		require.Error(t, err)
	})
}
