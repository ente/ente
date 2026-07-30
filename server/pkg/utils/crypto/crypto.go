package crypto

import (
	"encoding/base64"
	"encoding/hex"

	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
	"golang.org/x/crypto/curve25519"
)

// Exported constants matching libsodium
const (
	SecretBoxKeyBytes   = 32 // crypto_secretbox_KEYBYTES in libsodium
	SecretBoxNonceBytes = 24 // crypto_secretbox_NONCEBYTES in libsodium
	GenericHashBytes    = 32 // crypto_generichash_BYTES in libsodium (BLAKE2b-256)
	BoxPublicKeyBytes   = 32 // crypto_box_publickeybytes in lib-sodium
)

func Encrypt(data string, encryptionKey []byte) (ente.EncryptionResult, error) {
	return EncryptNative(data, encryptionKey)
}

func encryptWithNonce(data string, encryptionKey []byte, nonce []byte) (ente.EncryptionResult, error) {
	return encryptWithNonceNative(data, encryptionKey, nonce)
}

func Decrypt(cipher []byte, key []byte, nonce []byte) (string, error) {
	return DecryptNative(cipher, key, nonce)
}

func GetHash(data string, hashKey []byte) (string, error) {
	return GetHashNative(data, hashKey)
}

func GetEncryptedToken(token string, publicKey string) (string, error) {
	return GetEncryptedTokenNative(token, publicKey)
}

func ValidateSealedBoxPublicKey(publicKey string) error {
	_, err := decodeAndValidateSealedBoxPublicKey(publicKey)
	return err
}

func decodeAndValidateSealedBoxPublicKey(publicKey string) ([]byte, error) {
	publicKeyBytes, err := base64.StdEncoding.DecodeString(publicKey)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to decode public key")
	}
	if len(publicKeyBytes) != BoxPublicKeyBytes {
		return nil, stacktrace.NewError("invalid public key length")
	}

	// Reject low-order/non-contributory points so hostile clients cannot upload
	// a public key that collapses challenge encryption onto a trivial secret.
	probeScalar, err := hex.DecodeString("a5465c1d0f3f1e0d49f5cf0a5dbf3d74b2c1f5d9a604de884812a4ccf4a4c5f0")
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to initialize box public key validator")
	}
	if _, err := curve25519.X25519(probeScalar, publicKeyBytes); err != nil {
		return nil, stacktrace.Propagate(err, "invalid box public key")
	}
	return publicKeyBytes, nil
}
