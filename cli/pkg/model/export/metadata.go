package export

import (
	"slices"
	"time"
)

type AlbumMetadata struct {
	ID        int64  `json:"id"`
	OwnerID   int64  `json:"ownerID"`
	AlbumName string `json:"albumName"`
	IsDeleted bool   `json:"isDeleted"`
	// This is to handle the case where two accounts are exporting to the same directory
	// and a album is shared between them
	AccountOwnerIDs []int64 `json:"accountOwnerIDs"`

	// Folder name is the name of the disk folder that contains the album data
	// exclude this from json serialization
	FolderName string `json:"-"`
}

// AddAccountOwner adds the given account id to the list of account owners
// if it is not already present. Returns true if the account id was added
// and false otherwise
func (a *AlbumMetadata) AddAccountOwner(id int64) bool {
	if slices.Contains(a.AccountOwnerIDs, id) {
		return false
	}
	a.AccountOwnerIDs = append(a.AccountOwnerIDs, id)
	return true
}

// DiskFileMetadata is the metadata for a file when exported to disk
// For S3 compliant storage, we will introduce a new struct that will contain references to the albums
type DiskFileMetadata struct {
	Title            string    `json:"title"`
	Description      *string   `json:"description"`
	Location         *Location `json:"location"`
	CreationTime     time.Time `json:"creationTime"`
	ModificationTime time.Time `json:"modificationTime"`
	Info             *Info     `json:"info"`

	// exclude this from json serialization
	MetaFileName string `json:"-"`
}

func (d *DiskFileMetadata) AddFileName(fileName string) {
	if d.Info.FileNames == nil {
		d.Info.FileNames = make([]string, 0)
	}
	if slices.Contains(d.Info.FileNames, fileName) {
		return
	}
	d.Info.FileNames = append(d.Info.FileNames, fileName)
}

type Info struct {
	ID      int64   `json:"id"`
	Hash    *string `json:"hash"`
	OwnerID int64   `json:"ownerID"`
	// A file can contain multiple parts (example: live photos or burst photos)
	FileNames []string `json:"fileNames"`
}
