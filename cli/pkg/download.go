package pkg

import (
	"context"
	"fmt"
	"github.com/ente/cli/internal/crypto"
	"github.com/ente/cli/pkg/model"
	"github.com/ente/cli/utils"
	"github.com/ente/cli/utils/encoding"
	"log"
	"os"
)

func (c *ClICtrl) downloadAndDecrypt(
	ctx context.Context,
	file model.RemoteFile,
	deviceKey []byte,
) (*string, error) {
	dir := c.tempFolder
	downloadPath := fmt.Sprintf("%s/%d", dir, file.ID)
	if stat, err := os.Stat(downloadPath); err == nil && stat.Size() == file.Info.FileSize {
		log.Printf("File already exists %s (%s)", file.GetTitle(), utils.ByteCountDecimal(file.Info.FileSize))
	} else {
		log.Printf("Downloading %s (%s)", file.GetTitle(), utils.ByteCountDecimal(file.Info.FileSize))
		err := c.Client.DownloadFile(ctx, file.ID, downloadPath)
		if err != nil {
			return nil, fmt.Errorf("error downloading file %d: %w", file.ID, err)
		}
	}
	decryptedPath := fmt.Sprintf("%s/%d.decrypted", dir, file.ID)
	err := crypto.DecryptFile(downloadPath, decryptedPath, file.Key.MustDecrypt(deviceKey), encoding.DecodeBase64(file.FileNonce))
	if err != nil {
		log.Printf("Error decrypting file %d: %s", file.ID, err)
		return nil, model.ErrDecryption
	} else {
		_ = os.Remove(downloadPath)
	}
	return &decryptedPath, nil
}
