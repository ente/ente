package model

import (
	"github.com/ente/cli/internal/crypto"
	"github.com/ente/cli/utils/encoding"
	"log"
)

type EncString struct {
	CipherText string `json:"cipherText"`
	Nonce      string `json:"nonce"`
}

func MakeEncString(plainTextBytes []byte, key []byte) *EncString {
	cipher, nonce, err := crypto.EncryptChaCha20poly1305(plainTextBytes, key)
	if err != nil {
		log.Fatalf("failed to encrypt %s", err)
	}
	return &EncString{
		CipherText: encoding.EncodeBase64(cipher),
		Nonce:      encoding.EncodeBase64(nonce),
	}
}

func (e *EncString) MustDecrypt(key []byte) []byte {
	_, plainBytes, err := crypto.DecryptChaChaBase64(e.CipherText, key, e.Nonce)
	if err != nil {
		panic(err)
	}
	return plainBytes
}
