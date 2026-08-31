package pkg

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/ente/cli/pkg/model"
	"github.com/ente/cli/pkg/model/export"
	"log"
	"os"
	"strings"

	"path/filepath"
)

func (c *ClICtrl) createLocalFolderForRemoteAlbums(ctx context.Context, account model.Account) error {
	path := account.ExportDir
	albums, err := c.getRemoteAlbums(ctx)
	if err != nil {
		return err
	}
	userID := ctx.Value("user_id").(int64)
	albumIDToMetaMap, err := readFolderMetadata(path)
	if err != nil {
		return err
	}
	filter := ctx.Value(model.FilterKey).(model.Filter)
	for _, album := range albums {
		if filter.SkipAlbum(album, false) {
			continue
		}
		if album.IsDeleted {
			if meta, ok := albumIDToMetaMap[album.ID]; ok {
				log.Printf("Deleting album %s as it is deleted", meta.AlbumName)
				if err = os.RemoveAll(filepath.Join(path, meta.FolderName)); err != nil {
					return err
				}
				delete(albumIDToMetaMap, meta.ID)
			}
			continue
		}
		metaByID := albumIDToMetaMap[album.ID]

		if metaByID != nil && strings.EqualFold(metaByID.AlbumName, album.AlbumName) &&
			sanitizeAlbumFolderName(metaByID.FolderName) == metaByID.FolderName {
			continue
		}

		albumFolderName := sanitizeAlbumFolderName(album.AlbumName)
		albumFolderName, err = uniqueAlbumFolderName(path, albumFolderName)
		if err != nil {
			return err
		}

		albumPath := filepath.Join(path, albumFolderName)
		metaPath := filepath.Join(albumPath, ".meta")
		if metaByID == nil {
			log.Printf("Adding folder %s for album %s", albumFolderName, album.AlbumName)
			for _, p := range []string{albumPath, metaPath} {
				if err = os.Mkdir(p, 0755); err != nil {
					return err
				}
			}
		} else {
			oldAlbumPath := filepath.Join(path, metaByID.FolderName)
			log.Printf("Renaming path from %s to %s for album %s", oldAlbumPath, albumPath, album.AlbumName)
			if err = os.Rename(oldAlbumPath, albumPath); err != nil {
				return err
			}
		}
		metaFilePath := filepath.Join(path, albumFolderName, albumMetaFolder, albumMetaFile)
		metaData := export.AlbumMetadata{
			ID:              album.ID,
			OwnerID:         album.OwnerID,
			AlbumName:       album.AlbumName,
			IsDeleted:       album.IsDeleted,
			AccountOwnerIDs: []int64{userID},
			FolderName:      albumFolderName,
		}
		if err = writeJSONToFile(metaFilePath, metaData); err != nil {
			return err
		}
		albumIDToMetaMap[album.ID] = &metaData
	}
	return nil
}

func sanitizeAlbumFolderName(name string) string {
	name = strings.Map(func(r rune) rune {
		if r < ' ' || strings.ContainsRune(`<>:"/\|?*`, r) {
			return '_'
		}
		return r
	}, name)
	name = strings.TrimRight(strings.TrimSpace(name), ". ")
	if name == "" || isWindowsReservedName(name) {
		return "_" + name
	}
	return name
}

func isWindowsReservedName(name string) bool {
	base, _, _ := strings.Cut(name, ".")
	base = strings.ToUpper(strings.TrimRight(base, " "))
	switch base {
	case "CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$",
		"COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "COM¹", "COM²", "COM³",
		"LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9", "LPT¹", "LPT²", "LPT³":
		return true
	}
	return false
}

func uniqueAlbumFolderName(root, name string) (string, error) {
	for i := 0; ; i++ {
		candidate := name
		if i > 0 {
			candidate = fmt.Sprintf("%s_%d", name, i)
		}
		_, err := os.Lstat(filepath.Join(root, candidate))
		if os.IsNotExist(err) {
			return candidate, nil
		}
		if err != nil {
			return "", err
		}
	}
}

func readFolderMetadata(path string) (map[int64]*export.AlbumMetadata, error) {
	albumIDToMetadataMap := make(map[int64]*export.AlbumMetadata)
	entries, err := os.ReadDir(path)
	if err != nil {
		return nil, err
	}
	for _, entry := range entries {
		if entry.IsDir() {
			dirName := entry.Name()
			metaFilePath := filepath.Join(path, dirName, albumMetaFolder, albumMetaFile)
			if _, err := os.Stat(metaFilePath); err == nil {
				var metaData export.AlbumMetadata
				metaDataBytes, err := os.ReadFile(metaFilePath)
				if err != nil {
					continue // Skip this entry if reading fails
				}

				if err := json.Unmarshal(metaDataBytes, &metaData); err == nil {
					metaData.FolderName = dirName
					albumIDToMetadataMap[metaData.ID] = &metaData
				}
			}
		}
	}
	return albumIDToMetadataMap, nil
}
