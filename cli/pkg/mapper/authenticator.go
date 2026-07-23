package mapper

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/ente/cli/internal/api/models"
	eCrypto "github.com/ente/cli/internal/crypto"
)

func MapRemoteAuthEntityToString(ctx context.Context, authEntity models.AuthEntity, authKey []byte) (*string, error) {
	_, decrypted, err := eCrypto.DecryptChaChaBase64Auth(*authEntity.EncryptedData, authKey, *authEntity.Header)
	if err != nil {
		return nil, fmt.Errorf("failed to decrypt auth enityt %s: %v", authEntity.ID, err)
	}
	decryptedStr := string(decrypted)
	// json decode the string
	var jsonDecodedStr string
	err = json.Unmarshal([]byte(decryptedStr), &jsonDecodedStr)
	if err != nil {
		return nil, fmt.Errorf("failed to decode json %s: %v", decryptedStr, err)
	}
	return &jsonDecodedStr, nil
}
