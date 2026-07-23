package crypto

import (
	"crypto/rand"
	"encoding/base64"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/stacktrace"
	"golang.org/x/crypto/blake2b"
	"golang.org/x/crypto/nacl/box"
	"golang.org/x/crypto/nacl/secretbox"
)

func EncryptNative(data string, encryptionKey []byte) (ente.EncryptionResult, error) {
	return encryptWithNonceNative(data, encryptionKey, auth.GenerateRandomBytes(SecretBoxNonceBytes))
}

func encryptWithNonceNative(data string, encryptionKey []byte, nonce []byte) (ente.EncryptionResult, error) {
	// Convert key to array
	if len(encryptionKey) != SecretBoxKeyBytes {
		return ente.EncryptionResult{}, stacktrace.NewError("invalid key length")
	}
	var key [SecretBoxKeyBytes]byte
	copy(key[:], encryptionKey)

	// Convert nonce to array
	if len(nonce) != SecretBoxNonceBytes {
		return ente.EncryptionResult{}, stacktrace.NewError("invalid nonce length")
	}
	var nonceArray [SecretBoxNonceBytes]byte
	copy(nonceArray[:], nonce)

	// Encrypt using secretbox (XSalsa20-Poly1305)
	encrypted := secretbox.Seal(nil, []byte(data), &nonceArray, &key)

	return ente.EncryptionResult{
		Cipher: encrypted,
		Nonce:  nonce,
	}, nil
}

func DecryptNative(cipher []byte, encryptionKey []byte, nonce []byte) (string, error) {
	// Convert key to array
	if len(encryptionKey) != SecretBoxKeyBytes {
		return "", stacktrace.NewError("invalid key length")
	}
	var key [SecretBoxKeyBytes]byte
	copy(key[:], encryptionKey)

	// Convert nonce to array
	if len(nonce) != SecretBoxNonceBytes {
		return "", stacktrace.NewError("invalid nonce length")
	}
	var nonceArray [SecretBoxNonceBytes]byte
	copy(nonceArray[:], nonce)

	// Decrypt using secretbox
	decrypted, ok := secretbox.Open(nil, cipher, &nonceArray, &key)
	if !ok {
		return "", stacktrace.NewError("decryption failed")
	}

	return string(decrypted), nil
}

func GetHashNative(data string, hashKey []byte) (string, error) {
	// BLAKE2b-256 hash with optional key
	hash, err := blake2b.New256(hashKey)
	if err != nil {
		return "", stacktrace.Propagate(err, "failed to create blake2b hasher")
	}

	hash.Write([]byte(data))
	hashBytes := hash.Sum(nil)

	return base64.StdEncoding.EncodeToString(hashBytes), nil
}

// GetEncryptedTokenNative encrypts the given token using the recipient's public key.
// Format matches lib-sodium: https://libsodium.gitbook.io/doc/public-key_cryptography/sealed_boxes#algorithm-details
// ephemeral_pk ‖ box(m, recipient_pk, ephemeral_sk, nonce=blake2b(ephemeral_pk ‖ recipient_pk))
func GetEncryptedTokenNative(token string, publicKey string) (string, error) {
	publicKeyBytes, err := base64.StdEncoding.DecodeString(publicKey)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if len(publicKeyBytes) != BoxPublicKeyBytes {
		return "", stacktrace.NewError("invalid public key length")
	}

	tokenBytes, err := base64.URLEncoding.DecodeString(token)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}

	// Convert slice to array for nacl/box
	var recipientPublicKey [BoxPublicKeyBytes]byte
	copy(recipientPublicKey[:], publicKeyBytes)

	// Generate ephemeral keypair
	ephemeralPublicKey, ephemeralPrivateKey, err := box.GenerateKey(rand.Reader)
	if err != nil {
		return "", stacktrace.Propagate(err, "failed to generate ephemeral keypair")
	}

	// Derive nonce deterministically like libsodium's crypto_box_seal
	// nonce = BLAKE2b-192(ephemeral_pk || recipient_pk)
	nonceInput := make([]byte, 64)
	copy(nonceInput[:32], ephemeralPublicKey[:])
	copy(nonceInput[32:], recipientPublicKey[:])

	hash, err := blake2b.New(24, nil) // 24 bytes = 192 bits for nonce
	if err != nil {
		return "", stacktrace.Propagate(err, "failed to create blake2b hasher")
	}
	hash.Write(nonceInput)
	var nonce [24]byte
	copy(nonce[:], hash.Sum(nil))

	// Encrypt the message (ephemeral public key + ciphertext)
	out := make([]byte, BoxPublicKeyBytes) // just ephemeral public key
	copy(out, ephemeralPublicKey[:])
	encrypted := box.Seal(out, tokenBytes, &nonce, &recipientPublicKey, ephemeralPrivateKey)
	return base64.StdEncoding.EncodeToString(encrypted), nil
}
