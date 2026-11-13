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
	// Shared albums may be exported by multiple accounts into the same directory.
	AccountOwnerIDs []int64 `json:"accountOwnerIDs"`

	FolderName string `json:"-"`
}

func (a *AlbumMetadata) AddAccountOwner(id int64) bool {
	if slices.Contains(a.AccountOwnerIDs, id) {
		return false
	}
	a.AccountOwnerIDs = append(a.AccountOwnerIDs, id)
	return true
}

type DiskFileMetadata struct {
	Title            string    `json:"title"`
	Description      *string   `json:"description"`
	Location         *Location `json:"location"`
	CreationTime     time.Time `json:"creationTime"`
	ModificationTime time.Time `json:"modificationTime"`
	Info             *Info     `json:"info"`

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
	// Live and burst photos can contain multiple files.
	FileNames []string `json:"fileNames"`
}
