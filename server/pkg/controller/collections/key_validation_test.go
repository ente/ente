package collections

import (
	"encoding/base64"
	"net/http/httptest"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/gin-gonic/gin"
)

func b64OfLen(length int) string {
	return base64.StdEncoding.EncodeToString(make([]byte, length))
}

func TestValidateOwnedCollectionKey(t *testing.T) {
	tests := []struct {
		name                  string
		encryptedKeyLen       int
		keyDecryptionNonceLen int
		wantErr               bool
	}{
		{
			name:                  "accepts secretbox encrypted collection key",
			encryptedKeyLen:       encryptedCollectionKeyLen,
			keyDecryptionNonceLen: secretboxNonceBytes,
		},
		{
			name:                  "rejects short encrypted key",
			encryptedKeyLen:       encryptedCollectionKeyLen - 1,
			keyDecryptionNonceLen: secretboxNonceBytes,
			wantErr:               true,
		},
		{
			name:                  "rejects long encrypted key",
			encryptedKeyLen:       encryptedCollectionKeyLen + 1,
			keyDecryptionNonceLen: secretboxNonceBytes,
			wantErr:               true,
		},
		{
			name:                  "rejects short nonce",
			encryptedKeyLen:       encryptedCollectionKeyLen,
			keyDecryptionNonceLen: secretboxNonceBytes - 1,
			wantErr:               true,
		},
		{
			name:                  "rejects long nonce",
			encryptedKeyLen:       encryptedCollectionKeyLen,
			keyDecryptionNonceLen: secretboxNonceBytes + 1,
			wantErr:               true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := validateOwnedCollectionKey(
				b64OfLen(tt.encryptedKeyLen),
				b64OfLen(tt.keyDecryptionNonceLen),
			)
			if (err != nil) != tt.wantErr {
				t.Fatalf("validateOwnedCollectionKey() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestValidateSealedCollectionKey(t *testing.T) {
	tests := []struct {
		name    string
		keyLen  int
		wantErr bool
	}{
		{
			name:   "accepts sealed collection key",
			keyLen: sealedCollectionKeyLen,
		},
		{
			name:    "rejects sealed box for 33 byte plaintext key",
			keyLen:  sealedCollectionKeyLen + 1,
			wantErr: true,
		},
		{
			name:    "rejects short sealed key",
			keyLen:  sealedCollectionKeyLen - 1,
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := validateSealedCollectionKey(b64OfLen(tt.keyLen))
			if (err != nil) != tt.wantErr {
				t.Fatalf("validateSealedCollectionKey() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestValidateCollectionKeyRejectsInvalidBase64(t *testing.T) {
	if err := validateSealedCollectionKey("not-base64@@@"); err == nil {
		t.Fatal("validateSealedCollectionKey() error = nil, want error")
	}
	if err := validateOwnedCollectionKey("not-base64@@@", b64OfLen(secretboxNonceBytes)); err == nil {
		t.Fatal("validateOwnedCollectionKey() encryptedKey error = nil, want error")
	}
	if err := validateOwnedCollectionKey(b64OfLen(encryptedCollectionKeyLen), "not-base64@@@"); err == nil {
		t.Fatal("validateOwnedCollectionKey() keyDecryptionNonce error = nil, want error")
	}
}

func TestCollectionControllerRejectsInvalidCollectionKeysBeforeRepoAccess(t *testing.T) {
	controller := CollectionController{}
	ctx := testGinContext()

	if _, err := controller.Create(ente.Collection{
		EncryptedKey:       b64OfLen(encryptedCollectionKeyLen + 1),
		KeyDecryptionNonce: b64OfLen(secretboxNonceBytes),
		Type:               "album",
	}, 1); err == nil {
		t.Fatal("Create() error = nil, want invalid key error")
	}

	if _, err := controller.Share(ctx, ente.AlterShareRequest{
		CollectionID: 1,
		Email:        "sharee@example.com",
		EncryptedKey: b64OfLen(sealedCollectionKeyLen + 1),
	}); err == nil {
		t.Fatal("Share() error = nil, want invalid key error")
	}

	if err := controller.JoinViaLink(ctx, ente.JoinCollectionViaLinkRequest{
		CollectionID: 1,
		EncryptedKey: b64OfLen(sealedCollectionKeyLen + 1),
	}); err == nil {
		t.Fatal("JoinViaLink() error = nil, want invalid key error")
	}
}

func testGinContext() *gin.Context {
	recorder := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(recorder)
	ctx.Request = httptest.NewRequest("POST", "/", nil)
	return ctx
}
