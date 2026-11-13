package crypto

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"testing"

	"github.com/stretchr/testify/require"
	"golang.org/x/crypto/blake2b"
	"golang.org/x/crypto/nacl/box"
)

func TestSealedBoxRoundTrip(t *testing.T) {
	publicKey, privateKey, err := box.GenerateKey(rand.Reader)
	require.NoError(t, err)

	message := []byte("test-token-12345")
	sealedBase64, err := GetEncryptedToken(
		base64.URLEncoding.EncodeToString(message),
		base64.StdEncoding.EncodeToString(publicKey[:]),
	)
	require.NoError(t, err)

	sealed, err := base64.StdEncoding.DecodeString(sealedBase64)
	require.NoError(t, err)
	require.Len(t, sealed, boxPublicKeyBytes+box.Overhead+len(message))

	decrypted, err := openSealedBox(sealed, publicKey, privateKey)
	require.NoError(t, err)
	require.Equal(t, message, decrypted)
}

func openSealedBox(sealed []byte, publicKey, privateKey *[boxPublicKeyBytes]byte) ([]byte, error) {
	if len(sealed) < boxPublicKeyBytes+box.Overhead {
		return nil, errors.New("invalid sealed box length")
	}

	var ephemeralPublicKey [boxPublicKeyBytes]byte
	copy(ephemeralPublicKey[:], sealed[:boxPublicKeyBytes])

	nonceInput := make([]byte, boxPublicKeyBytes*2)
	copy(nonceInput[:boxPublicKeyBytes], ephemeralPublicKey[:])
	copy(nonceInput[boxPublicKeyBytes:], publicKey[:])

	hash, err := blake2b.New(boxNonceBytes, nil)
	if err != nil {
		return nil, err
	}
	hash.Write(nonceInput)

	var nonce [boxNonceBytes]byte
	copy(nonce[:], hash.Sum(nil))

	decrypted, ok := box.Open(nil, sealed[boxPublicKeyBytes:], &nonce, &ephemeralPublicKey, privateKey)
	if !ok {
		return nil, errors.New("failed to open sealed box")
	}
	return decrypted, nil
}
