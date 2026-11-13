package crypto

import (
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"github.com/minio/blake2b-simd"
	"golang.org/x/crypto/argon2"
)

const (
	loginSubKeyLen     = 32
	loginSubKeyId      = 1
	loginSubKeyContext = "loginctx"

	decryptionBufferSize = 4 * 1024 * 1024
)
const (
	cryptoKDFBlake2bBytesMin              = 16
	cryptoKDFBlake2bBytesMax              = 64
	cryptoGenerichashBlake2bSaltBytes     = 16
	cryptoGenerichashBlake2bPersonalBytes = 16
	BoxSealBytes                          = 48 // 32 for the ephemeral public key + 16 for the MAC
)

var (
	ErrOpenBox       = errors.New("failed to open box")
	ErrSealedOpenBox = errors.New("failed to open sealed box")
)

const ()

func DeriveArgonKey(password, salt string, memLimit, opsLimit int) ([]byte, error) {
	if memLimit < 1024 || opsLimit < 1 {
		return nil, fmt.Errorf("invalid memory or operation limits")
	}

	saltBytes, err := base64.StdEncoding.DecodeString(salt)
	if err != nil {
		return nil, fmt.Errorf("invalid salt: %v", err)
	}

	key := argon2.IDKey([]byte(password), saltBytes, uint32(opsLimit), uint32(memLimit/1024), 1, 32)

	return key, nil
}

func DeriveLoginKey(keyEncKey []byte) []byte {
	subKey, _ := deriveSubKey(keyEncKey, loginSubKeyContext, loginSubKeyId, loginSubKeyLen)
	return subKey[:16]
}

func deriveSubKey(masterKey []byte, context string, subKeyID uint64, subKeyLength uint32) ([]byte, error) {
	if subKeyLength < cryptoKDFBlake2bBytesMin || subKeyLength > cryptoKDFBlake2bBytesMax {
		return nil, fmt.Errorf("subKeyLength out of bounds")
	}
	ctxPadded := make([]byte, cryptoGenerichashBlake2bPersonalBytes)
	copy(ctxPadded, []byte(context))
	salt := make([]byte, cryptoGenerichashBlake2bSaltBytes)
	binary.LittleEndian.PutUint64(salt, subKeyID)

	config := &blake2b.Config{
		Size:   uint8(subKeyLength),
		Key:    masterKey,
		Salt:   salt,
		Person: ctxPadded,
	}
	hasher, err := blake2b.New(config)
	if err != nil {
		return nil, err
	}
	hasher.Write(nil)
	return hasher.Sum(nil), nil
}

func DecryptChaChaBase64(data string, key []byte, nonce string) (string, []byte, error) {
	dataBytes, err := base64.StdEncoding.DecodeString(data)
	if err != nil {
		// safe to log the encrypted data
		return "", nil, fmt.Errorf("invalid base64 data %s: %v", data, err)
	}
	nonceBytes, err := base64.StdEncoding.DecodeString(nonce)
	if err != nil {
		return "", nil, fmt.Errorf("invalid nonce: %v", err)
	}
	decryptedData, err := decryptChaCha20poly1305(dataBytes, key, nonceBytes)
	if err != nil {
		return "", nil, fmt.Errorf("failed to decrypt data: %v", err)
	}
	return base64.StdEncoding.EncodeToString(decryptedData), decryptedData, nil
}

func DecryptChaChaBase64Auth(data string, key []byte, nonce string) (string, []byte, error) {
	dataBytes, err := base64.StdEncoding.DecodeString(data)
	if err != nil {
		// safe to log the encrypted data
		return "", nil, fmt.Errorf("invalid base64 data %s: %v", data, err)
	}
	nonceBytes, err := base64.StdEncoding.DecodeString(nonce)
	if err != nil {
		return "", nil, fmt.Errorf("invalid nonce: %v", err)
	}
	decryptedData, err := decryptChaCha20poly1305V2(dataBytes, key, nonceBytes)
	if err != nil {
		return "", nil, fmt.Errorf("failed to decrypt data: %v", err)
	}
	return base64.StdEncoding.EncodeToString(decryptedData), decryptedData, nil
}
