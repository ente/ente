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
	folderToMetaMap, albumIDToMetaMap, err := readFolderMetadata(path)
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
				delete(folderToMetaMap, meta.FolderName)
				delete(albumIDToMetaMap, meta.ID)
			}
			continue
		}
		metaByID := albumIDToMetaMap[album.ID]

		if metaByID != nil {
			if strings.EqualFold(metaByID.AlbumName, album.AlbumName) {
				//log.Printf("Skipping album %s as it already exists", album.AlbumName)
				continue
			}
		}

		albumFolderName := filepath.Clean(album.AlbumName)
		// replace : with _
		albumFolderName = strings.ReplaceAll(albumFolderName, ":", "_")
		albumFolderName = strings.ReplaceAll(albumFolderName, "/", "_")
		albumFolderName = strings.TrimSpace(albumFolderName)

		albumID := album.ID

		if _, ok := folderToMetaMap[albumFolderName]; ok {
			for i := 1; ; i++ {
				newAlbumName := fmt.Sprintf("%s_%d", albumFolderName, i)
				if _, ok := folderToMetaMap[newAlbumName]; !ok {
					albumFolderName = newAlbumName
					break
				}
			}
		}
		// Create album and meta folders if they don't exist
		albumPath := filepath.Clean(filepath.Join(path, albumFolderName))
		metaPath := filepath.Join(albumPath, ".meta")
		if metaByID == nil {
			log.Printf("Adding folder %s for album %s", albumFolderName, album.AlbumName)
			for _, p := range []string{albumPath, metaPath} {
				if _, err := os.Stat(p); os.IsNotExist(err) {
					if err = os.Mkdir(p, 0755); err != nil {
						return err
					}
				}
			}
		} else {
			// rename meta.FolderName to albumFolderName
			oldAlbumPath := filepath.Join(path, metaByID.FolderName)
			log.Printf("Renaming path from %s to %s for album %s", oldAlbumPath, albumPath, album.AlbumName)
			if err = os.Rename(oldAlbumPath, albumPath); err != nil {
				return err
			}
		}
		// Handle meta file
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
		folderToMetaMap[albumFolderName] = &metaData
		albumIDToMetaMap[albumID] = &metaData
	}
	return nil
}

// readFolderMetadata returns a map of folder name to album metadata for all folders in the given path
// and a map of album ID to album metadata for all albums in the given path.
func readFolderMetadata(path string) (map[string]*export.AlbumMetadata, map[int64]*export.AlbumMetadata, error) {
	result := make(map[string]*export.AlbumMetadata)
	albumIdToMetadataMap := make(map[int64]*export.AlbumMetadata)
	// Read the top-level directories in the given path
	entries, err := os.ReadDir(path)
	if err != nil {
		return nil, nil, err
	}
	for _, entry := range entries {
		if entry.IsDir() {
			dirName := entry.Name()
			metaFilePath := filepath.Join(path, dirName, albumMetaFolder, albumMetaFile)
			// Initialize as nil, will remain nil if JSON file is not found or not readable
			result[dirName] = nil
			// Read the JSON file if it exists
			if _, err := os.Stat(metaFilePath); err == nil {
				var metaData export.AlbumMetadata
				metaDataBytes, err := os.ReadFile(metaFilePath)
				if err != nil {
					continue // Skip this entry if reading fails
				}

				if err := json.Unmarshal(metaDataBytes, &metaData); err == nil {
					metaData.FolderName = dirName
					result[dirName] = &metaData
					albumIdToMetadataMap[metaData.ID] = &metaData
				}
			}
		}
	}
	return result, albumIdToMetadataMap, nil
}
