package main

import (
	"encoding/base64"
	"fmt"
	"github.com/ente/museum/pkg/utils/auth"
)

func main() {
	keyLen := 32
	hashByteLen := 64
	keyBytes := auth.GenerateRandomBytes(keyLen)
	key := base64.StdEncoding.EncodeToString(keyBytes)

	hashBytes := auth.GenerateRandomBytes(hashByteLen)
	hash := base64.StdEncoding.EncodeToString(hashBytes)

	jwtBytes := auth.GenerateRandomBytes(keyLen)
	jwt := base64.URLEncoding.EncodeToString(jwtBytes)

	fmt.Printf("key.encryption: %s\n", key)
	fmt.Printf("key.hash: %s\n", hash)
	fmt.Printf("jwt.secret: %s\n", jwt)
}
