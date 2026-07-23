package secrets

import (
	"context"
	"fmt"
	"github.com/ente/cli/internal/api"
	"github.com/ente/cli/internal/api/models"
	eCrypto "github.com/ente/cli/internal/crypto"
	"github.com/ente/cli/pkg/model"
	"github.com/ente/cli/utils/encoding"
)

type KeyHolder struct {
	// DeviceKey is the key used to encrypt/decrypt the data while storing sensitive
	// information on the disk. Usually, it should be stored in OS Keychain.
	DeviceKey      []byte
	AccountSecrets map[string]*model.AccSecretInfo
	CollectionKeys map[string][]byte
}

func NewKeyHolder(deviceKey []byte) *KeyHolder {
	if len(deviceKey) != 32 {
		panic(fmt.Sprintf("device key must be 32 bytes, found: %d bytes", len(deviceKey)))
	}
	return &KeyHolder{
		AccountSecrets: make(map[string]*model.AccSecretInfo),
		CollectionKeys: make(map[string][]byte),
		DeviceKey:      deviceKey,
	}
}

// LoadSecrets loads the secrets for a given account using the provided CLI key.
// It decrypts the token key, master key, and secret key using the CLI key.
// The decrypted keys and the decoded public key are stored in the AccountSecrets map using the account key as the map key.
// It returns the account secret information or an error if the decryption fails.
func (k *KeyHolder) LoadSecrets(account model.Account) (*model.AccSecretInfo, error) {
	tokenKey := account.Token.MustDecrypt(k.DeviceKey)
	masterKey := account.MasterKey.MustDecrypt(k.DeviceKey)
	secretKey := account.SecretKey.MustDecrypt(k.DeviceKey)
	k.AccountSecrets[account.AccountKey()] = &model.AccSecretInfo{
		Token:     tokenKey,
		MasterKey: masterKey,
		SecretKey: secretKey,
		PublicKey: encoding.DecodeBase64(account.PublicKey),
	}
	return k.AccountSecrets[account.AccountKey()], nil
}

func (k *KeyHolder) GetAccountSecretInfo(ctx context.Context) *model.AccSecretInfo {
	accountKey := ctx.Value("account_key").(string)
	return k.AccountSecrets[accountKey]
}

// GetCollectionKey retrieves the key for a given collection.
// It first fetches the account secret information from the context.
// If the collection owner's ID matches the user ID from the context, it decrypts the collection key using the master key.
// If the collection is shared (i.e., the owner's ID does not match the user ID), it decrypts the collection key using the public and secret keys.
// It returns the decrypted collection key or an error if the decryption fails.
func (k *KeyHolder) GetCollectionKey(ctx context.Context, collection api.Collection) ([]byte, error) {
	accSecretInfo := k.GetAccountSecretInfo(ctx)
	userID := ctx.Value("user_id").(int64)
	if collection.Owner.ID == userID {
		collKey, err := eCrypto.SecretBoxOpen(
			encoding.DecodeBase64(collection.EncryptedKey),
			encoding.DecodeBase64(collection.KeyDecryptionNonce),
			accSecretInfo.MasterKey)
		if err != nil {
			return nil, fmt.Errorf("collection %d key drive failed %s", collection.ID, err)
		}
		return collKey, nil
	} else {
		collKey, err := eCrypto.SealedBoxOpen(encoding.DecodeBase64(collection.EncryptedKey),
			accSecretInfo.PublicKey, accSecretInfo.SecretKey)
		if err != nil {
			return nil, fmt.Errorf("shared collection %d key drive failed %s", collection.ID, err)
		}
		return collKey, nil
	}
}

func (k *KeyHolder) GetAuthenticatorKey(ctx context.Context, authKey models.AuthKey) ([]byte, error) {
	accSecretInfo := k.GetAccountSecretInfo(ctx)
	userID := ctx.Value("user_id").(int64)
	if authKey.UserID == userID {
		key, keyErr := eCrypto.SecretBoxOpen(
			encoding.DecodeBase64(authKey.EncryptedKey),
			encoding.DecodeBase64(authKey.Header),
			accSecretInfo.MasterKey)
		if keyErr != nil {
			return nil, fmt.Errorf("auth key %d drive failed %s", authKey.UserID, keyErr)
		}
		return key, nil
	}
	return nil, fmt.Errorf("accountSecInfo not found for user  %d", authKey.UserID)
}
