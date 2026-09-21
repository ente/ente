package collections

import (
	"encoding/base64"
	"errors"
	"strconv"

	"github.com/ente/museum/ente"
)

const (
	collectionKeyBytes        = 32
	secretboxMACBytes         = 16
	secretboxNonceBytes       = 24
	sealedBoxOverheadBytes    = 48
	encryptedCollectionKeyLen = collectionKeyBytes + secretboxMACBytes
	sealedCollectionKeyLen    = collectionKeyBytes + sealedBoxOverheadBytes
)

func validateOwnedCollectionKey(encryptedKey string, keyDecryptionNonce string) error {
	if err := validateBase64DecodedLength(encryptedKey, encryptedCollectionKeyLen, "encryptedKey"); err != nil {
		return err
	}
	return validateBase64DecodedLength(keyDecryptionNonce, secretboxNonceBytes, "keyDecryptionNonce")
}

func validateSealedCollectionKey(encryptedKey string) error {
	return validateBase64DecodedLength(encryptedKey, sealedCollectionKeyLen, "encryptedKey")
}

func validateCollectionFileItems(files []ente.CollectionFileItem) error {
	for _, file := range files {
		if file.ID == 0 {
			return ente.NewBadRequestWithMessage("file ID is required")
		}
		if err := validateOwnedCollectionKey(file.EncryptedKey, file.KeyDecryptionNonce); err != nil {
			return ente.NewBadRequestWithMessage(err.Error())
		}
	}
	return nil
}

func validateBase64DecodedLength(value string, expected int, field string) error {
	if len(value) != base64.StdEncoding.EncodedLen(expected) {
		return errors.New(field + " must decode to " + strconv.Itoa(expected) + " bytes")
	}
	decoded, err := base64.StdEncoding.DecodeString(value)
	if err != nil {
		return errors.New(field + " must be valid base64")
	}
	if len(decoded) != expected {
		return errors.New(field + " must decode to " + strconv.Itoa(expected) + " bytes")
	}
	return nil
}
