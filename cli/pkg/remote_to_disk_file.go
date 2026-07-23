package pkg

import (
	"archive/zip"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/ente/cli/pkg/mapper"
	"github.com/ente/cli/pkg/model"
	"github.com/ente/cli/pkg/model/export"
	"github.com/ente/cli/utils"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func (c *ClICtrl) syncFiles(ctx context.Context, account model.Account) error {
	log.Printf("Starting file download")
	exportRoot := account.ExportDir
	_, albumIDToMetaMap, err := readFolderMetadata(exportRoot)
	if err != nil {
		return err
	}
	albumsToSkip := make(map[int64]bool)
	filter := ctx.Value(model.FilterKey).(model.Filter)
	remoteAlbums, readAlbumErr := c.getRemoteAlbums(ctx)
	if readAlbumErr != nil {
		return readAlbumErr
	}
	for _, album := range remoteAlbums {
		if !album.IsDeleted && filter.SkipAlbum(album, false) {
			albumsToSkip[album.ID] = true
		}
	}
	entries, err := c.getRemoteAlbumEntries(ctx)
	if err != nil {
		return err
	}
	log.Println("total entries", len(entries))
	model.SortAlbumFileEntry(entries)
	defer utils.TimeTrack(time.Now(), "process_files")
	var albumDiskInfo *albumDiskInfo
	for i, albumFileEntry := range entries {
		if albumFileEntry.SyncedLocally {
			continue
		}
		if _, ok := albumsToSkip[albumFileEntry.AlbumID]; ok {
			continue
		}
		albumInfo, ok := albumIDToMetaMap[albumFileEntry.AlbumID]
		if !ok {
			log.Printf("Album %d not found in local metadata", albumFileEntry.AlbumID)
			continue
		}
		if albumInfo.IsDeleted {
			putErr := c.DeleteAlbumEntry(ctx, albumFileEntry)
			if putErr != nil {
				return putErr
			}
			continue
		}

		if albumDiskInfo == nil || albumDiskInfo.AlbumMeta.ID != albumInfo.ID {
			albumDiskInfo, err = readFilesMetadata(exportRoot, albumInfo)
			if err != nil {
				return err
			}
		}
		fileBytes, err := c.GetValue(ctx, model.RemoteFiles, fmt.Appendf(nil, "%d", albumFileEntry.FileID))
		if err != nil {
			return err
		}
		if fileBytes != nil {
			var existingEntry *model.RemoteFile
			err = json.Unmarshal(fileBytes, &existingEntry)
			if err != nil {
				return err
			}
			log.Printf("[%d/%d] Sync %s for album %s", i, len(entries), existingEntry.GetTitle(), albumInfo.AlbumName)
			err = c.downloadEntry(ctx, albumDiskInfo, *existingEntry, albumFileEntry)
			if err != nil {
				if errors.Is(err, model.ErrDecryption) {
					continue
				} else if existingEntry.IsLivePhoto() && errors.Is(err, zip.ErrFormat) {
					log.Printf("err processing live photo %s (%d), %s", existingEntry.GetTitle(), existingEntry.ID, err.Error())
					continue
				} else if existingEntry.IsLivePhoto() && errors.Is(err, model.ErrLiveZip) {
					continue
				} else if model.IsBadTimeStampError(err) {
					log.Printf("Skipping file due to error %s (%d)", existingEntry.GetTitle(), existingEntry.ID)
					log.Printf("CreationTime %v, ModidicationTime %v", existingEntry.GetCreationTime(), existingEntry.GetModificationTime())
					continue
				} else {
					return err
				}
			}
		} else {
			// file metadata is missing in the localDB
			if albumFileEntry.IsDeleted {
				delErr := c.DeleteAlbumEntry(ctx, albumFileEntry)
				if delErr != nil {
					log.Fatalf("Error deleting album entry %d (deleted: %v)  %v", albumFileEntry.FileID, albumFileEntry.IsDeleted, delErr)
				}
			} else {
				log.Fatalf("Failed to find entry in db for file %d (deleted: %v)", albumFileEntry.FileID, albumFileEntry.IsDeleted)
			}
		}
	}

	return nil
}

func (c *ClICtrl) downloadEntry(ctx context.Context,
	diskInfo *albumDiskInfo,
	file model.RemoteFile,
	albumEntry *model.AlbumFileEntry,
) error {
	if !diskInfo.AlbumMeta.IsDeleted && albumEntry.IsDeleted {
		albumEntry.IsDeleted = true
		diskFileMeta := diskInfo.GetDiskFileMetadata(file)
		if diskFileMeta != nil {
			removeErr := removeDiskFile(diskFileMeta, diskInfo)
			if removeErr != nil {
				return removeErr
			}
		}
		delErr := c.DeleteAlbumEntry(ctx, albumEntry)
		if delErr != nil {
			return delErr
		}
		return nil
	}
	diskFileMeta := diskInfo.GetDiskFileMetadata(file)
	if diskFileMeta != nil {
		removeErr := removeDiskFile(diskFileMeta, diskInfo)
		if removeErr != nil {
			return removeErr
		}
	}
	if !diskInfo.IsFilePresent(file) {
		decrypt, err := c.downloadAndDecrypt(ctx, file, c.KeyHolder.DeviceKey)
		if err != nil {
			return err
		}
		fileDiskMetadata := mapper.MapRemoteFileToDiskMetadata(file)
		// Get the extension
		extension := filepath.Ext(fileDiskMetadata.Title)
		baseFileName := strings.TrimSuffix(filepath.Clean(filepath.Base(fileDiskMetadata.Title)), extension)
		diskMetaFileName := diskInfo.GenerateUniqueMetaFileName(baseFileName, extension)
		if file.IsLivePhoto() {
			imagePath, videoPath, err := UnpackLive(*decrypt)
			if err != nil {
				return err
			}
			if imagePath == "" && videoPath == "" {
				log.Printf("imagePath %s, videoPath %s", imagePath, videoPath)
				return model.ErrLiveZip
			}
			if imagePath != "" {
				imageExtn := filepath.Ext(imagePath)
				imageFileName := diskInfo.GenerateUniqueFileName(baseFileName, imageExtn)
				imageFilePath := filepath.Join(diskInfo.ExportRoot, diskInfo.AlbumMeta.FolderName, imageFileName)
				moveErr := Move(imagePath, imageFilePath)
				if moveErr != nil {
					return moveErr
				}
				fileDiskMetadata.AddFileName(imageFileName)
			}
			if videoPath != "" {
				videoExtn := filepath.Ext(videoPath)
				videoFileName := diskInfo.GenerateUniqueFileName(baseFileName, videoExtn)
				videoFilePath := filepath.Join(diskInfo.ExportRoot, diskInfo.AlbumMeta.FolderName, videoFileName)
				// move the decrypt file to filePath
				moveErr := Move(videoPath, videoFilePath)
				if moveErr != nil {
					return moveErr
				}
				fileDiskMetadata.AddFileName(videoFileName)
			}
		} else {
			fileName := diskInfo.GenerateUniqueFileName(baseFileName, extension)
			filePath := filepath.Join(diskInfo.ExportRoot, diskInfo.AlbumMeta.FolderName, fileName)
			// move the decrypt file to filePath
			err = Move(*decrypt, filePath)
			if err != nil {
				return err
			}
			fileDiskMetadata.AddFileName(fileName)
		}

		fileDiskMetadata.MetaFileName = diskMetaFileName
		err = diskInfo.AddEntry(fileDiskMetadata)
		if err != nil {
			return err
		}

		err = writeJSONToFile(filepath.Join(diskInfo.ExportRoot, diskInfo.AlbumMeta.FolderName, ".meta", diskMetaFileName), fileDiskMetadata)
		if err != nil {
			return err
		}
		albumEntry.SyncedLocally = true
		putErr := c.UpsertAlbumEntry(ctx, albumEntry)
		if putErr != nil {
			return putErr
		}
	}
	return nil
}

func removeDiskFile(diskFileMeta *export.DiskFileMetadata, diskInfo *albumDiskInfo) error {
	// remove the file from disk
	log.Printf("Removing file %s from disk", diskFileMeta.MetaFileName)
	err := os.Remove(filepath.Join(diskInfo.ExportRoot, diskInfo.AlbumMeta.FolderName, ".meta", diskFileMeta.MetaFileName))
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	for _, fileName := range diskFileMeta.Info.FileNames {
		err = os.Remove(filepath.Join(diskInfo.ExportRoot, diskInfo.AlbumMeta.FolderName, fileName))
		if err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	return diskInfo.RemoveEntry(diskFileMeta)
}

// readFolderMetadata reads the metadata of the files in the given path
// For disk export, a particular albums files are stored in a folder named after the album.
// Inside the folder, the files are stored at top level and its metadata is stored in a .meta folder
func readFilesMetadata(home string, albumMeta *export.AlbumMetadata) (*albumDiskInfo, error) {
	albumMetadataFolder := filepath.Join(home, albumMeta.FolderName, albumMetaFolder)
	albumPath := filepath.Join(home, albumMeta.FolderName)
	// verify the both the album folder and the .meta folder exist
	if _, err := os.Stat(albumMetadataFolder); err != nil {
		return nil, err
	}
	if _, err := os.Stat(albumPath); err != nil {
		return nil, err
	}
	result := make(map[string]*export.DiskFileMetadata)
	//fileNameToFileName := make(map[string]*export.DiskFileMetadata)
	fileIdToMetadata := make(map[int64]*export.DiskFileMetadata)
	claimedFileName := make(map[string]bool)
	// Read the top-level directories in the given path
	albumFileEntries, err := os.ReadDir(albumPath)
	if err != nil {
		return nil, err
	}
	for _, entry := range albumFileEntries {
		if !entry.IsDir() {
			claimedFileName[strings.ToLower(entry.Name())] = true
		}
	}
	metaEntries, err := os.ReadDir(albumMetadataFolder)
	if err != nil {
		return nil, err
	}
	for _, entry := range metaEntries {
		if !entry.IsDir() {
			fileName := entry.Name()
			if fileName == albumMetaFile {
				continue
			}
			if !strings.HasSuffix(fileName, ".json") {
				log.Printf("Skipping file %s as it is not a JSON file", fileName)
				continue
			}
			fileMetadataPath := filepath.Join(albumMetadataFolder, fileName)
			// Initialize as nil, will remain nil if JSON file is not found or not readable
			result[strings.ToLower(fileName)] = nil
			// Read the JSON file if it exists
			var metaData export.DiskFileMetadata
			metaDataBytes, err := os.ReadFile(fileMetadataPath)
			if err != nil {
				continue // Skip this entry if reading fails
			}
			if err := json.Unmarshal(metaDataBytes, &metaData); err == nil {
				metaData.MetaFileName = fileName
				result[strings.ToLower(fileName)] = &metaData
				fileIdToMetadata[metaData.Info.ID] = &metaData
			}
		}
	}
	return &albumDiskInfo{
		ExportRoot:                home,
		AlbumMeta:                 albumMeta,
		FileNames:                 &claimedFileName,
		MetaFileNameToDiskFileMap: &result,
		FileIdToDiskFileMap:       &fileIdToMetadata,
	}, nil
}
