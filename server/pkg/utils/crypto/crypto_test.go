package crypto

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestErrorCases(t *testing.T) {
	validKey := generateTestKey()

	t.Run("invalid_key_length", func(t *testing.T) {
		shortKey := []byte("too-short")

		_, err := Encrypt("test", shortKey)
		require.Error(t, err)

		_, err = Decrypt([]byte("test"), shortKey, []byte("nonce"))
		require.Error(t, err)
	})

	t.Run("invalid_nonce_length", func(t *testing.T) {
		encrypted, err := Encrypt("test", validKey)
		require.NoError(t, err)

		_, err = Decrypt(encrypted.Cipher, validKey, []byte("short"))
		require.Error(t, err)
	})

	t.Run("tampered_ciphertext", func(t *testing.T) {
		encrypted, err := Encrypt("test", validKey)
		require.NoError(t, err)

		cipher := append([]byte(nil), encrypted.Cipher...)
		cipher[0] ^= 0xff

		_, err = Decrypt(cipher, validKey, encrypted.Nonce)
		require.Error(t, err)
	})

	t.Run("wrong_key", func(t *testing.T) {
		wrongKey := generateTestKey()
		wrongKey[0] ^= 0xff

		encrypted, err := Encrypt("test", validKey)
		require.NoError(t, err)

		_, err = Decrypt(encrypted.Cipher, wrongKey, encrypted.Nonce)
		require.Error(t, err)
	})
}

func generateTestKey() []byte {
	key := make([]byte, secretBoxKeyBytes)
	for i := range key {
		key[i] = byte(i)
	}
	return key
}
