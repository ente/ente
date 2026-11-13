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
	// DeviceKey encrypts secrets stored on disk and normally lives in the OS keychain.
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
