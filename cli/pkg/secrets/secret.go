package secrets

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"github.com/ente/cli/utils/constants"
	"log"
	"os"

	"github.com/zalando/go-keyring"
)

func IsRunningInContainer() bool {
	if _, err := os.Stat("/.dockerenv"); err != nil {
		return false
	}
	return true
}

const (
	secretService = "ente"
	secretUser    = "ente-cli-user"
	keyLength     = 32
)

func GetOrCreateClISecret() []byte {
	// get password
	secret, err := keyring.Get(secretService, secretUser)

	if err != nil {
		if !errors.Is(err, keyring.ErrNotFound) {
			if secretsFile := os.Getenv("ENTE_CLI_SECRETS_PATH"); secretsFile != "" {
				return GetSecretFromSecretText(secretsFile)
			}
			if IsRunningInContainer() {
				return GetSecretFromSecretText(fmt.Sprintf("%s.secret.txt", constants.CliDataPath))
			} else {
				log.Fatal(fmt.Errorf(`error getting password from keyring: %w
          Refer to https://ente.com/help/self-hosting/troubleshooting/cli
          `, err))
			}
		}
		key := make([]byte, keyLength)
		rand.Read(key)
		// Store the key as a base64 encoded string
		secret = base64.StdEncoding.EncodeToString(key)
		keySetErr := keyring.Set(secretService, secretUser, secret)
		if keySetErr != nil {
			log.Fatal(fmt.Errorf("error setting password in keyring: %w", keySetErr))
		}
	}
	// Try to decode the secret as base64
	decodedSecret, err := base64.StdEncoding.DecodeString(secret)
	if err == nil && len(decodedSecret) == keyLength {
		// If successful and the length is correct, return the decoded secret
		return decodedSecret
	}
	// If decoding fails or the length is incorrect, treat it as a legacy key
	legacySecret := []byte(secret)
	if len(legacySecret) != keyLength {
		// See https://github.com/ente/ente/issues/1510#issuecomment-2331676096 for more information
		log.Println("Warning: Existing key is not 32 bytes. Deleting it")
		delErr := keyring.Delete(secretService, secretUser)
		if delErr != nil {
			log.Fatal(fmt.Errorf("error deleting legacy key: %w", delErr))
		} else {
			log.Println("Warning: Trying to create a new key")
			return GetOrCreateClISecret()
		}
	}
	// If it's a keyLength-byte legacy key, return it as-is
	return legacySecret
}

// GetSecretFromSecretText reads the scecret from the secret text file.
// If the file does not exist, it will be created and write random keyLength bytes secret to it.
func GetSecretFromSecretText(secretFilePath string) []byte {

	// Check if file exists
	_, err := os.Stat(secretFilePath)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			log.Fatal(fmt.Errorf("error checking secret file: %w", err))
		}
		// File does not exist; create and write a random 32-byte secret
		key := make([]byte, keyLength)
		rand.Read(key)
		err = os.WriteFile(secretFilePath, key, 0644)
		if err != nil {
			log.Fatal(fmt.Errorf("error writing to secret file: %w", err))
		}
		return key
	}
	// File exists; read the secret
	secret, err := os.ReadFile(secretFilePath)
	if err != nil {
		log.Fatal(fmt.Errorf("error reading from secret file: %w", err))
	}
	if len(secret) != keyLength {
		log.Fatal(fmt.Errorf("error reading from secret file: expected %d bytes, got %d", keyLength, len(secret)))
	}
	return secret
}
