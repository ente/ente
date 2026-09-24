package pkg

import (
	"archive/zip"
	"context"
	"fmt"
	"github.com/ente/cli/internal/crypto"
	"github.com/ente/cli/pkg/model"
	"github.com/ente/cli/utils"
	"github.com/ente/cli/utils/encoding"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
)

// Suffixes of the temporary artifacts a single entry leaves behind in the CLI
// temp folder: the encrypted download itself, its decrypted copy, and the
// scratch directory a live photo zip is unpacked into. None of them are needed
// once the entry has been moved into the export, and leaving them behind fills
// up the temp filesystem (/tmp on most Linux systems) until downloads start
// failing with "no space left on device" (#6551).
const (
	decryptedTempSuffix = ".decrypted"
	unpackedTempSuffix  = ".live"
)

// tempPath returns the path of a temporary artifact belonging to fileID inside
// the CLI temp folder.
func (c *ClICtrl) tempPath(fileID int64, suffix string) string {
	return fmt.Sprintf("%s/%d%s", c.tempFolder, fileID, suffix)
}

// downloadAndDecrypt downloads file into the CLI temp folder and decrypts it
// there. The returned path is a temporary artifact owned by the caller, which
// is expected to remove it (moving it into the export removes it as well) once
// it is no longer needed. Every artifact created here is removed before an
// error is returned.
func (c *ClICtrl) downloadAndDecrypt(
	ctx context.Context,
	file model.RemoteFile,
	deviceKey []byte,
) (*string, error) {
	downloadPath := c.tempPath(file.ID, "")
	if stat, err := os.Stat(downloadPath); err == nil && stat.Size() == file.Info.FileSize {
		log.Printf("File already exists %s (%s)", file.GetTitle(), utils.ByteCountDecimal(file.Info.FileSize))
	} else {
		log.Printf("Downloading %s (%s)", file.GetTitle(), utils.ByteCountDecimal(file.Info.FileSize))
		err := c.Client.DownloadFile(ctx, file.ID, downloadPath)
		if err != nil {
			// A failed download leaves a partial file behind, which would occupy
			// the temp filesystem until the entry is retried.
			_ = os.Remove(downloadPath)
			return nil, fmt.Errorf("error downloading file %d: %w", file.ID, err)
		}
	}
	decryptedPath := c.tempPath(file.ID, decryptedTempSuffix)
	err := crypto.DecryptFile(downloadPath, decryptedPath, file.Key.MustDecrypt(deviceKey), encoding.DecodeBase64(file.FileNonce))
	if err != nil {
		log.Printf("Error decrypting file %d: %s", file.ID, err)
		_ = os.Remove(downloadPath)
		_ = os.Remove(decryptedPath)
		return nil, model.ErrDecryption
	}
	_ = os.Remove(downloadPath)
	return &decryptedPath, nil
}

// UnpackLive unpacks the live photo zip at src into unpackDir and returns the
// paths of the image and the video it holds. unpackDir is owned by the caller,
// which must remove it once the unpacked files have been moved into the export.
func UnpackLive(src, unpackDir string) (imagePath, videoPath string, retErr error) {
	var filenames []string
	reader, err := zip.OpenReader(src)
	if reader != nil {
		defer reader.Close()
	}
	if err != nil {
		retErr = err
		return
	}

	for _, file := range reader.File {
		if !filepath.IsLocal(file.Name) {
			retErr = fmt.Errorf("invalid file path in live photo zip %s: %w", file.Name, zip.ErrInsecurePath)
			return
		}
		destFilePath := filepath.Join(unpackDir, file.Name)
		filenames = append(filenames, destFilePath)

		destDir := filepath.Dir(destFilePath)
		if err := os.MkdirAll(destDir, 0755); err != nil {
			retErr = err
			return
		}

		destFile, err := os.Create(destFilePath)
		if err != nil {
			retErr = err
			return
		}
		defer destFile.Close()

		srcFile, err := file.Open()
		if err != nil {
			retErr = err
			return
		}
		defer srcFile.Close()

		_, err = io.Copy(destFile, srcFile)
		if err != nil {
			retErr = err
			return
		}
	}
	for _, filepath := range filenames {
		if strings.Contains(strings.ToLower(filepath), "image") {
			imagePath = filepath
		} else if strings.Contains(strings.ToLower(filepath), "video") {
			videoPath = filepath
		} else {
			retErr = fmt.Errorf("unexpcted file in zip %s", filepath)
		}
	}
	return
}
