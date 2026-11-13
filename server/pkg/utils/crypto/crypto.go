package crypto

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/stacktrace"
	"golang.org/x/crypto/blake2b"
	"golang.org/x/crypto/curve25519"
	"golang.org/x/crypto/nacl/box"
	"golang.org/x/crypto/nacl/secretbox"
)

const (
	secretBoxKeyBytes   = 32 // crypto_secretbox_KEYBYTES in libsodium
	secretBoxNonceBytes = 24 // crypto_secretbox_NONCEBYTES in libsodium
	boxPublicKeyBytes   = 32 // crypto_box_publickeybytes in lib-sodium
	boxNonceBytes       = 24 // crypto_box_NONCEBYTES in libsodium
)

func Encrypt(data string, encryptionKey []byte) (ente.EncryptionResult, error) {
	nonce := auth.GenerateRandomBytes(secretBoxNonceBytes)
	if len(encryptionKey) != secretBoxKeyBytes {
		return ente.EncryptionResult{}, stacktrace.NewError("invalid key length")
	}
	var key [secretBoxKeyBytes]byte
	copy(key[:], encryptionKey)

	var nonceArray [secretBoxNonceBytes]byte
	copy(nonceArray[:], nonce)

	encrypted := secretbox.Seal(nil, []byte(data), &nonceArray, &key)

	return ente.EncryptionResult{
		Cipher: encrypted,
		Nonce:  nonce,
	}, nil
}

func Decrypt(cipher []byte, encryptionKey []byte, nonce []byte) (string, error) {
	if len(encryptionKey) != secretBoxKeyBytes {
		return "", stacktrace.NewError("invalid key length")
	}
	var key [secretBoxKeyBytes]byte
	copy(key[:], encryptionKey)

	if len(nonce) != secretBoxNonceBytes {
		return "", stacktrace.NewError("invalid nonce length")
	}
	var nonceArray [secretBoxNonceBytes]byte
	copy(nonceArray[:], nonce)

	decrypted, ok := secretbox.Open(nil, cipher, &nonceArray, &key)
	if !ok {
		return "", stacktrace.NewError("decryption failed")
	}

	return string(decrypted), nil
}

func GetHash(data string, hashKey []byte) (string, error) {
	hash, err := blake2b.New256(hashKey)
	if err != nil {
		return "", stacktrace.Propagate(err, "failed to create blake2b hasher")
	}

	hash.Write([]byte(data))
	hashBytes := hash.Sum(nil)

	return base64.StdEncoding.EncodeToString(hashBytes), nil
}

// Wire-compatible with libsodium's crypto_box_seal.
func GetEncryptedToken(token string, publicKey string) (string, error) {
	publicKeyBytes, err := base64.StdEncoding.DecodeString(publicKey)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if len(publicKeyBytes) != boxPublicKeyBytes {
		return "", stacktrace.NewError("invalid public key length")
	}

	tokenBytes, err := base64.URLEncoding.DecodeString(token)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}

	var recipientPublicKey [boxPublicKeyBytes]byte
	copy(recipientPublicKey[:], publicKeyBytes)

	ephemeralPublicKey, ephemeralPrivateKey, err := box.GenerateKey(rand.Reader)
	if err != nil {
		return "", stacktrace.Propagate(err, "failed to generate ephemeral keypair")
	}

	// crypto_box_seal derives the nonce from both public keys.
	nonceInput := make([]byte, boxPublicKeyBytes*2)
	copy(nonceInput[:boxPublicKeyBytes], ephemeralPublicKey[:])
	copy(nonceInput[boxPublicKeyBytes:], recipientPublicKey[:])

	hash, err := blake2b.New(boxNonceBytes, nil)
	if err != nil {
		return "", stacktrace.Propagate(err, "failed to create blake2b hasher")
	}
	hash.Write(nonceInput)
	var nonce [boxNonceBytes]byte
	copy(nonce[:], hash.Sum(nil))

	// crypto_box_seal prefixes the ciphertext with the ephemeral public key.
	out := make([]byte, boxPublicKeyBytes)
	copy(out, ephemeralPublicKey[:])
	encrypted := box.Seal(out, tokenBytes, &nonce, &recipientPublicKey, ephemeralPrivateKey)
	return base64.StdEncoding.EncodeToString(encrypted), nil
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
	if len(publicKeyBytes) != boxPublicKeyBytes {
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
