package crypto

import (
	"crypto/rand"
	"encoding/base64"
	"testing"
)

const (
	password           = "test_password"
	kdfSalt            = "vd0dcYMGNLKn/gpT6uTFTw=="
	memLimit           = 64 * 1024 * 1024 // 64MB
	opsLimit           = 2
	cipherText         = "kBXQ2PuX6y/aje5r22H0AehRPh6sQ0ULoeAO"
	cipherNonce        = "v7wsI+BFZsRMIjDm3rTxPhmi/CaUdkdJ"
	expectedPlainText  = "plain_text"
	expectedDerivedKey = "vp8d8Nee0BbIML4ab8Cp34uYnyrN77cRwTl920flyT0="
)

func TestDeriveArgonKey(t *testing.T) {
	derivedKey, err := DeriveArgonKey(password, kdfSalt, memLimit, opsLimit)
	if err != nil {
		t.Fatalf("Failed to derive key: %v", err)
	}

	if base64.StdEncoding.EncodeToString(derivedKey) != expectedDerivedKey {
		t.Fatalf("Derived key does not match expected key")
	}
}

func TestDecryptChaCha20poly1305(t *testing.T) {
	derivedKey, err := DeriveArgonKey(password, kdfSalt, memLimit, opsLimit)
	if err != nil {
		t.Fatalf("Failed to derive key: %v", err)
	}
	decodedCipherText, err := base64.StdEncoding.DecodeString(cipherText)
	if err != nil {
		t.Fatalf("Failed to decode cipher text: %v", err)
	}

	decodedCipherNonce, err := base64.StdEncoding.DecodeString(cipherNonce)
	if err != nil {
		t.Fatalf("Failed to decode cipher nonce: %v", err)
	}

	decryptedText, err := decryptChaCha20poly1305(decodedCipherText, derivedKey, decodedCipherNonce)
	if err != nil {
		t.Fatalf("Failed to decrypt: %v", err)
	}
	if string(decryptedText) != expectedPlainText {
		t.Fatalf("Decrypted text : %s does not match the expected text: %s", string(decryptedText), expectedPlainText)
	}
}

func TestEncryptAndDecryptChaCha20Ploy1305(t *testing.T) {
	key := make([]byte, 32)
	rand.Read(key)
	cipher, nonce, err := EncryptChaCha20poly1305([]byte("plain_text"), key)
	if err != nil {
		return
	}
	plainText, err := decryptChaCha20poly1305(cipher, key, nonce)
	if err != nil {
		t.Fatalf("Failed to decrypt: %v", err)
	}
	if string(plainText) != "plain_text" {
		t.Fatalf("Decrypted text : %s does not match the expected text: %s", string(plainText), "plain_text")
	}
}

func TestSecretBoxOpenBase64(t *testing.T) {
	sealedCipherText := "KHwRN+RzvTu+jC7mCdkMsqnTPSLvevtZILmcR2OYFbIRPqDyjAl+m8KxD9B5fiEo"
	sealNonce := "jgfPDOsQh2VdIHWJVSBicMPF2sQW3HIY"
	sealKey, _ := base64.StdEncoding.DecodeString("kercNpvGufMTTHmDwAhz26DgCAvznd1+/buBqKEkWr4=")
	expectedSealedText := "O1ObUBMv+SCE1qWHD7+WViEIZcAeTp18Y+m9eMlDE1Y="

	plainText, err := SecretBoxOpenBase64(sealedCipherText, sealNonce, sealKey)
	if err != nil {
		t.Fatalf("Failed to decrypt: %v", err)
	}

	if expectedSealedText != base64.StdEncoding.EncodeToString(plainText) {
		t.Fatalf("Decrypted text : %s does not match the expected text: %s", string(plainText), expectedSealedText)
	}
}
