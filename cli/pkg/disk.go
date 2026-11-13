package pkg

import (
	"encoding/json"
	"errors"
	"fmt"
	"github.com/ente/cli/pkg/model"
	"github.com/ente/cli/pkg/model/export"
	"io"
	"os"
	"strings"
)

const (
	albumMetaFile   = "album_meta.json"
	albumMetaFolder = ".meta"
)

type albumDiskInfo struct {
	ExportRoot string
	AlbumMeta  *export.AlbumMetadata
	// FileNames tracks files at the root of the album directory.
	FileNames                 *map[string]bool
	MetaFileNameToDiskFileMap *map[string]*export.DiskFileMetadata
	FileIdToDiskFileMap       *map[int64]*export.DiskFileMetadata
}

func (a *albumDiskInfo) IsFilePresent(file model.RemoteFile) bool {
	_, ok := (*a.FileIdToDiskFileMap)[file.ID]
	return ok
}

func (a *albumDiskInfo) IsFileNamePresent(fileName string) bool {
	_, ok := (*a.FileNames)[strings.ToLower(fileName)]
	return ok
}

func (a *albumDiskInfo) AddEntry(metadata *export.DiskFileMetadata) error {
	if _, ok := (*a.FileIdToDiskFileMap)[metadata.Info.ID]; ok {
		return errors.New("fileID already present")
	}
	if _, ok := (*a.MetaFileNameToDiskFileMap)[strings.ToLower(metadata.MetaFileName)]; ok {
		return errors.New("fileName already present")
	}
	(*a.MetaFileNameToDiskFileMap)[strings.ToLower(metadata.MetaFileName)] = metadata
	(*a.FileIdToDiskFileMap)[metadata.Info.ID] = metadata
	for _, filename := range metadata.Info.FileNames {
		if _, ok := (*a.FileNames)[strings.ToLower(filename)]; ok {
			return errors.New("fileName already present")
		}
		(*a.FileNames)[strings.ToLower(filename)] = true
	}
	return nil
}

func (a *albumDiskInfo) RemoveEntry(metadata *export.DiskFileMetadata) error {
	if _, ok := (*a.FileIdToDiskFileMap)[metadata.Info.ID]; !ok {
		return errors.New("fileID not present")
	}
	if _, ok := (*a.MetaFileNameToDiskFileMap)[strings.ToLower(metadata.MetaFileName)]; !ok {
		return errors.New("fileName not present")
	}
	delete(*a.MetaFileNameToDiskFileMap, strings.ToLower(metadata.MetaFileName))
	delete(*a.FileIdToDiskFileMap, metadata.Info.ID)
	for _, filename := range metadata.Info.FileNames {
		delete(*a.FileNames, strings.ToLower(filename))
	}
	return nil
}

func (a *albumDiskInfo) IsMetaFileNamePresent(metaFileName string) bool {
	_, ok := (*a.MetaFileNameToDiskFileMap)[strings.ToLower(metaFileName)]
	return ok
}

func (a *albumDiskInfo) GenerateUniqueMetaFileName(baseFileName, extension string) string {
	potentialDiskFileName := fmt.Sprintf("%s%s.json", baseFileName, extension)
	count := 1
	for a.IsMetaFileNamePresent(potentialDiskFileName) {
		fileName := fmt.Sprintf("%s_%d", baseFileName, count)
		potentialDiskFileName = fmt.Sprintf("%s%s.json", fileName, extension)
		count++
		if !a.IsMetaFileNamePresent(potentialDiskFileName) {
			break
		}
	}
	return potentialDiskFileName
}

func (a *albumDiskInfo) GenerateUniqueFileName(baseFileName, extension string) string {
	fileName := fmt.Sprintf("%s%s", baseFileName, extension)
	count := 1
	for a.IsFileNamePresent(strings.ToLower(fileName)) {
		fileName = fmt.Sprintf("%s_%d%s", baseFileName, count, extension)
		count++
		if !a.IsFileNamePresent(strings.ToLower(fileName)) {
			break
		}
	}
	return fileName
}

func (a *albumDiskInfo) GetDiskFileMetadata(file model.RemoteFile) *export.DiskFileMetadata {
	diskFile, ok := (*a.FileIdToDiskFileMap)[file.ID]
	if !ok {
		return nil
	}
	return diskFile
}

func writeJSONToFile(filePath string, data interface{}) error {
	file, err := os.Create(filePath)
	if err != nil {
		return err
	}
	defer file.Close()

	encoder := json.NewEncoder(file)
	encoder.SetIndent("", "  ")
	return encoder.Encode(data)
}

func readJSONFromFile(filePath string, data interface{}) error {
	file, err := os.Open(filePath)
	if err != nil {
		return err
	}
	defer file.Close()

	decoder := json.NewDecoder(file)
	return decoder.Decode(data)
}

func Move(source, destination string) error {
	err := os.Rename(source, destination)
	if err != nil {
		return moveCrossDevice(source, destination)
	}
	return err
}

func moveCrossDevice(source, destination string) error {
	src, err := os.Open(source)
	if err != nil {
		return err
	}
	dst, err := os.Create(destination)
	if err != nil {
		src.Close()
		return err
	}
	_, err = io.Copy(dst, src)
	src.Close()
	dst.Close()
	if err != nil {
		return err
	}
	fi, err := os.Stat(source)
	if err != nil {
		os.Remove(destination)
		return err
	}
	err = os.Chmod(destination, fi.Mode())
	if err != nil {
		os.Remove(destination)
		return err
	}
	os.Remove(source)
	return nil
}
