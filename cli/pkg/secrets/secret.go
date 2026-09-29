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
		secret = base64.StdEncoding.EncodeToString(key)
		keySetErr := keyring.Set(secretService, secretUser, secret)
		if keySetErr != nil {
			log.Fatal(fmt.Errorf("error setting password in keyring: %w", keySetErr))
		}
	}
	decodedSecret, err := base64.StdEncoding.DecodeString(secret)
	if err == nil && len(decodedSecret) == keyLength {
		return decodedSecret
	}
	// Older versions stored the raw key instead of base64.
	legacySecret := []byte(secret)
	if len(legacySecret) != keyLength {
		// Invalid legacy keys are regenerated: https://github.com/ente/ente/issues/1510#issuecomment-2331676096
		log.Println("Warning: Existing key is not 32 bytes. Deleting it")
		delErr := keyring.Delete(secretService, secretUser)
		if delErr != nil {
			log.Fatal(fmt.Errorf("error deleting legacy key: %w", delErr))
		} else {
			log.Println("Warning: Trying to create a new key")
			return GetOrCreateClISecret()
		}
	}
	return legacySecret
}

func GetSecretFromSecretText(secretFilePath string) []byte {
	_, err := os.Stat(secretFilePath)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			log.Fatal(fmt.Errorf("error checking secret file: %w", err))
		}
		key := make([]byte, keyLength)
		rand.Read(key)
		err = createSecretFile(secretFilePath, key)
		if err != nil {
			log.Fatal(fmt.Errorf("error writing to secret file: %w", err))
		}
		return key
	}
	secret, err := os.ReadFile(secretFilePath)
	if err != nil {
		log.Fatal(fmt.Errorf("error reading from secret file: %w", err))
	}
	if len(secret) != keyLength {
		log.Fatal(fmt.Errorf("error reading from secret file: expected %d bytes, got %d", keyLength, len(secret)))
	}
	return secret
}

func createSecretFile(path string, secret []byte) error {
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	_, writeErr := file.Write(secret)
	closeErr := file.Close()
	if writeErr != nil {
		return writeErr
	}
	return closeErr
}
