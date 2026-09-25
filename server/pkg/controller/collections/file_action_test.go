package collections

import (
	"errors"
	"strings"
	"testing"

	"github.com/ente/museum/ente"
)

func TestMoveFilesRejectsSameCollection(t *testing.T) {
	const collectionID = int64(1)
	err := (&CollectionController{}).MoveFiles(nil, ente.MoveFilesRequest{
		FromCollectionID: collectionID,
		ToCollectionID:   collectionID,
	})
	var apiErr *ente.ApiError
	if !errors.As(err, &apiErr) || apiErr.Code != ente.BadRequest {
		t.Fatalf("MoveFiles() error = %v, want %s", err, ente.BadRequest)
	}
}

func TestCollectionFileActionsRejectInvalidItems(t *testing.T) {
	controller := &CollectionController{}
	valid := ente.CollectionFileItem{
		ID:                 1,
		EncryptedKey:       b64OfLen(encryptedCollectionKeyLen),
		KeyDecryptionNonce: b64OfLen(secretboxNonceBytes),
	}
	if err := validateCollectionFileItems([]ente.CollectionFileItem{valid}); err != nil {
		t.Fatalf("valid item rejected: %v", err)
	}
	add := func(files []ente.CollectionFileItem) error { return controller.AddFiles(nil, 1, files, 1) }
	restore := func(files []ente.CollectionFileItem) error { return controller.RestoreFiles(nil, 1, 1, files) }
	move := func(files []ente.CollectionFileItem) error {
		return controller.MoveFiles(nil, ente.MoveFilesRequest{FromCollectionID: 1, ToCollectionID: 2, Files: files})
	}
	copyFiles := func(files []ente.CollectionFileItem) error {
		return controller.IsCopyAllowed(nil, 1, ente.CopyFileSyncRequest{SrcCollectionID: 1, DstCollection: 2, CollectionFileItems: files})
	}
	tests := []struct {
		name    string
		invalid ente.CollectionFileItem
		call    func([]ente.CollectionFileItem) error
	}{
		{"add missing ID", ente.CollectionFileItem{EncryptedKey: valid.EncryptedKey, KeyDecryptionNonce: valid.KeyDecryptionNonce}, add},
		{"add short key", ente.CollectionFileItem{ID: 2, EncryptedKey: b64OfLen(encryptedCollectionKeyLen - 1), KeyDecryptionNonce: valid.KeyDecryptionNonce}, add},
		{"restore missing key", ente.CollectionFileItem{ID: 2, KeyDecryptionNonce: valid.KeyDecryptionNonce}, restore},
		{"move missing nonce", ente.CollectionFileItem{ID: 2, EncryptedKey: valid.EncryptedKey}, move},
		{"copy missing ID", ente.CollectionFileItem{EncryptedKey: valid.EncryptedKey, KeyDecryptionNonce: valid.KeyDecryptionNonce}, copyFiles},
		{"copy short key", ente.CollectionFileItem{ID: 2, EncryptedKey: b64OfLen(encryptedCollectionKeyLen - 1), KeyDecryptionNonce: valid.KeyDecryptionNonce}, copyFiles},
		{"copy invalid base64 key", ente.CollectionFileItem{ID: 2, EncryptedKey: strings.Repeat("!", len(valid.EncryptedKey)), KeyDecryptionNonce: valid.KeyDecryptionNonce}, copyFiles},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.call([]ente.CollectionFileItem{valid, tt.invalid})
			var apiErr *ente.ApiError
			if !errors.As(err, &apiErr) || apiErr.Code != ente.BadRequest {
				t.Fatalf("error = %v, want %s", err, ente.BadRequest)
			}
		})
	}
}

func TestIsRemoveAllowedNilRoleDoesNotPanic(t *testing.T) {
	controller := &CollectionController{}
	const owner = int64(1)
	const actor = int64(2)

	t.Run("actor lacks role on owner-owned files", func(t *testing.T) {
		err := controller.isRemoveAllowed(nil, actor, owner, nil, map[int64][]int64{owner: {10}})
		if err == nil || !strings.Contains(err.Error(), "role none") {
			t.Fatalf("isRemoveAllowed() error = %v, want message containing %q", err, "role none")
		}
	})

	t.Run("actor lacks role on others' files", func(t *testing.T) {
		err := controller.isRemoveAllowed(nil, actor, owner, nil, map[int64][]int64{actor: {10}, 3: {11}})
		if err == nil {
			t.Fatalf("isRemoveAllowed() error = nil, want permission denied")
		}
	})
}
