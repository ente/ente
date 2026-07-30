package mapper

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/ente/cli/internal/api"
	eCrypto "github.com/ente/cli/internal/crypto"
	"github.com/ente/cli/pkg/model"
	"github.com/ente/cli/pkg/model/export"
	"github.com/ente/cli/pkg/secrets"
	"github.com/ente/cli/utils/encoding"
	"log"
)

func MapCollectionToAlbum(ctx context.Context, collection api.Collection, holder *secrets.KeyHolder) (*model.RemoteAlbum, error) {
	var album model.RemoteAlbum
	userID := ctx.Value("user_id").(int64)
	album.OwnerID = collection.Owner.ID
	album.ID = collection.ID
	album.IsShared = collection.Owner.ID != userID
	album.LastUpdatedAt = collection.UpdationTime
	album.IsDeleted = collection.IsDeleted
	collectionKey, err := holder.GetCollectionKey(ctx, collection)
	if err != nil {
		return nil, err
	}
	album.AlbumKey = *model.MakeEncString(collectionKey, holder.DeviceKey)
	var name string
	if collection.EncryptedName != "" {
		decrName, err := eCrypto.SecretBoxOpenBase64(collection.EncryptedName, collection.NameDecryptionNonce, collectionKey)
		if err != nil {
			log.Fatalf("failed to decrypt collection name: %v", err)
		}
		name = string(decrName)
	} else {
		// Early beta users (friends & family) might have collections without encrypted names
		name = collection.Name
	}
	album.AlbumName = name
	if collection.MagicMetadata != nil {
		_, encodedJsonBytes, err := eCrypto.DecryptChaChaBase64(collection.MagicMetadata.Data, collectionKey, collection.MagicMetadata.Header)
		if err != nil {
			return nil, fmt.Errorf("failed to decrypt magic metadata for collection %d: %w", collection.ID, err)
		}
		err = json.Unmarshal(encodedJsonBytes, &album.PrivateMeta)
		if err != nil {
			return nil, err
		}
	}
	if collection.PublicMagicMetadata != nil {
		_, encodedJsonBytes, err := eCrypto.DecryptChaChaBase64(collection.PublicMagicMetadata.Data, collectionKey, collection.PublicMagicMetadata.Header)
		if err != nil {
			return nil, fmt.Errorf("failed to decrypt public magic metadata for collection %d: %w", collection.ID, err)
		}
		err = json.Unmarshal(encodedJsonBytes, &album.PublicMeta)
		if err != nil {
			return nil, fmt.Errorf("failed to unmarshal public magic metadata for collection %d: %w", collection.ID, err)
		}
	}
	if album.IsShared && collection.SharedMagicMetadata != nil {
		_, encodedJsonBytes, err := eCrypto.DecryptChaChaBase64(collection.SharedMagicMetadata.Data, collectionKey, collection.SharedMagicMetadata.Header)
		if err != nil {
			return nil, fmt.Errorf("failed to decrypt shared magic metadata for collection %d: %w", collection.ID, err)
		}
		err = json.Unmarshal(encodedJsonBytes, &album.SharedMeta)
		if err != nil {
			return nil, fmt.Errorf("failed to unmarshal shared magic metadata for collection %d: %w", collection.ID, err)
		}
	}
	return &album, nil
}

func MapApiFileToPhotoFile(ctx context.Context, album model.RemoteAlbum, file api.File, holder *secrets.KeyHolder) (*model.RemoteFile, error) {
	if file.IsRemovedFromAlbum() {
		return nil, errors.New("file is deleted")
	}
	albumKey := album.AlbumKey.MustDecrypt(holder.DeviceKey)
	fileKey, err := eCrypto.SecretBoxOpen(
		encoding.DecodeBase64(file.EncryptedKey),
		encoding.DecodeBase64(file.KeyDecryptionNonce),
		albumKey)
	if err != nil {
		return nil, err
	}
	var photoFile model.RemoteFile
	photoFile.ID = file.ID
	photoFile.LastUpdateTime = file.UpdationTime
	photoFile.Key = *model.MakeEncString(fileKey, holder.DeviceKey)
	photoFile.FileNonce = file.File.DecryptionHeader
	photoFile.ThumbnailNonce = file.Thumbnail.DecryptionHeader
	photoFile.OwnerID = file.OwnerID
	if file.Info != nil {
		photoFile.Info = model.Info{
			FileSize:      file.Info.FileSize,
			ThumbnailSize: file.Info.ThumbnailSize,
		}
	}
	if file.Metadata.DecryptionHeader != "" {
		_, encodedJsonBytes, err := eCrypto.DecryptChaChaBase64(file.Metadata.EncryptedData, fileKey, file.Metadata.DecryptionHeader)
		if err != nil {
			return nil, fmt.Errorf("failed to decrypt metadata for file %d: %w", file.ID, err)
		}
		err = json.Unmarshal(encodedJsonBytes, &photoFile.Metadata)
		if err != nil {
			return nil, err
		}
	}
	if file.MagicMetadata != nil {
		_, encodedJsonBytes, err := eCrypto.DecryptChaChaBase64(file.MagicMetadata.Data, fileKey, file.MagicMetadata.Header)
		if err != nil {
			return nil, fmt.Errorf("failed to decrypt magic metadata for file %d: %w", file.ID, err)
		}
		err = json.Unmarshal(encodedJsonBytes, &photoFile.PrivateMetadata)
		if err != nil {
			return nil, err
		}
	}
	if file.PubicMagicMetadata != nil {
		_, encodedJsonBytes, err := eCrypto.DecryptChaChaBase64(file.PubicMagicMetadata.Data, fileKey, file.PubicMagicMetadata.Header)
		if err != nil {
			return nil, fmt.Errorf("failed to decrypt public magic metadata for file %d: %w", file.ID, err)
		}
		err = json.Unmarshal(encodedJsonBytes, &photoFile.PublicMetadata)
		if err != nil {
			return nil, err
		}
	}
	return &photoFile, nil
}

func MapRemoteFileToDiskMetadata(file model.RemoteFile) *export.DiskFileMetadata {
	return &export.DiskFileMetadata{
		Title:            file.GetTitle(),
		Description:      file.GetCaption(),
		CreationTime:     file.GetCreationTime(),
		ModificationTime: file.GetModificationTime(),
		Location:         file.GetLatlong(),
		Info: &export.Info{
			ID:      file.ID,
			Hash:    file.GetFileHash(),
			OwnerID: file.OwnerID,
		},
	}
}
