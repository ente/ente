package collections

import "github.com/ente/museum/ente"

const (
	collectionKeyBytes        = 32
	secretboxMACBytes         = 16
	secretboxNonceBytes       = 24
	sealedBoxOverheadBytes    = 48
	encryptedCollectionKeyLen = collectionKeyBytes + secretboxMACBytes
	sealedCollectionKeyLen    = collectionKeyBytes + sealedBoxOverheadBytes
)

func validateOwnedCollectionKey(encryptedKey string, keyDecryptionNonce string) error {
	if err := ente.ValidateBase64Length(encryptedKey, encryptedCollectionKeyLen); err != nil {
		return err
	}
	return ente.ValidateBase64Length(keyDecryptionNonce, secretboxNonceBytes)
}

func validateSealedCollectionKey(encryptedKey string) error {
	return ente.ValidateBase64Length(encryptedKey, sealedCollectionKeyLen)
}

func validateCollectionFileItems(files []ente.CollectionFileItem) error {
	for _, file := range files {
		if file.ID == 0 {
			return ente.NewBadRequestWithMessage("file ID is required")
		}
		if err := validateOwnedCollectionKey(file.EncryptedKey, file.KeyDecryptionNonce); err != nil {
			return err
		}
	}
	return nil
}
