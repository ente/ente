package model

import (
	"crypto/rand"
	"testing"
)

func TestEncString(t *testing.T) {
	key := make([]byte, 32)
	rand.Read(key)
	data := "dataToEncrypt"
	encData := MakeEncString([]byte(data), key)
	decryptedData := encData.MustDecrypt(key)
	if string(decryptedData) != data {
		t.Fatalf("decrypted data is not equal to original data")
	}
}
