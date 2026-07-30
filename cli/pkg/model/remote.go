package model

import (
	"fmt"
	"github.com/ente/cli/pkg/model/export"
	"sort"
	"time"
)

type FileType int8

const (
	Image FileType = iota
	Video
	LivePhoto
	Unknown = 127
)

type RemoteFile struct {
	ID              int64                  `json:"id"`
	OwnerID         int64                  `json:"ownerID"`
	Key             EncString              `json:"key"`
	LastUpdateTime  int64                  `json:"lastUpdateTime"`
	FileNonce       string                 `json:"fileNonce"`
	ThumbnailNonce  string                 `json:"thumbnailNonce"`
	Metadata        map[string]interface{} `json:"metadata"`
	PrivateMetadata map[string]interface{} `json:"privateMetadata"`
	PublicMetadata  map[string]interface{} `json:"publicMetadata"`
	Info            Info                   `json:"info"`
}

type Info struct {
	FileSize      int64 `json:"fileSize,omitempty"`
	ThumbnailSize int64 `json:"thumbSize,omitempty"`
}

type RemoteAlbum struct {
	ID            int64                  `json:"id"`
	OwnerID       int64                  `json:"ownerID"`
	IsShared      bool                   `json:"isShared"`
	IsDeleted     bool                   `json:"isDeleted"`
	AlbumName     string                 `json:"albumName"`
	AlbumKey      EncString              `json:"albumKey"`
	PublicMeta    map[string]interface{} `json:"publicMeta"`
	PrivateMeta   map[string]interface{} `json:"privateMeta"`
	SharedMeta    map[string]interface{} `json:"sharedMeta"`
	LastUpdatedAt int64                  `json:"lastUpdatedAt"`
}

func (r *RemoteAlbum) IsHidden() bool {
	if value, ok := r.PrivateMeta["visibility"]; ok {
		return int64(value.(float64)) == int64(2)
	}
	return false
}

type AlbumFileEntry struct {
	FileID        int64 `json:"fileID"`
	AlbumID       int64 `json:"albumID"`
	IsDeleted     bool  `json:"isDeleted"`
	SyncedLocally bool  `json:"localSync"`
}

// SortAlbumFileEntry sorts the given entries by isDeleted and then by albumID
func SortAlbumFileEntry(entries []*AlbumFileEntry) {
	sort.Slice(entries, func(i, j int) bool {
		if entries[i].IsDeleted != entries[j].IsDeleted {
			return entries[i].IsDeleted && !entries[j].IsDeleted
		}
		return entries[i].AlbumID < entries[j].AlbumID
	})
}

func (r *RemoteFile) GetFileType() FileType {
	value, ok := r.Metadata["fileType"]
	if !ok {
		panic("fileType not found in metadata")
	}
	switch int8(value.(float64)) {
	case 0:
		return Image
	case 1:
		return Video
	case 2:
		return LivePhoto
	}
	panic(fmt.Sprintf("invalid fileType %d", value.(int8)))
}

func (r *RemoteFile) IsLivePhoto() bool {
	return r.GetFileType() == LivePhoto
}

func (r *RemoteFile) GetFileHash() *string {
	value, ok := r.Metadata["hash"]
	if !ok {
		if r.IsLivePhoto() {
			imageHash, hasImgHash := r.Metadata["imageHash"]
			vidHash, hasVidHash := r.Metadata["videoHash"]
			if hasImgHash && hasVidHash {
				hash := fmt.Sprintf("%s:%s", imageHash, vidHash)
				return &hash
			}
		}
		return nil
	}
	if str, ok := value.(string); ok {
		return &str
	}
	return nil
}

func (r *RemoteFile) GetTitle() string {
	if r.PublicMetadata != nil {
		if value, ok := r.PublicMetadata["editedName"]; ok {
			return value.(string)
		}
	}
	value, ok := r.Metadata["title"]
	if !ok {
		panic("title not found in metadata")
	}
	return value.(string)
}

func (r *RemoteFile) GetCaption() *string {
	if r.PublicMetadata != nil {
		if value, ok := r.PublicMetadata["caption"]; ok {
			if str, ok := value.(string); ok {
				return &str
			}
		}
	}
	return nil
}

func (r *RemoteFile) GetCreationTime() time.Time {

	if r.PublicMetadata != nil {
		if value, ok := r.PublicMetadata["editedTime"]; ok && value.(float64) != 0 {
			return time.UnixMicro(int64(value.(float64)))
		}
	}
	value, ok := r.Metadata["creationTime"]
	if !ok {
		panic("creationTime not found in metadata")
	}
	return time.UnixMicro(int64(value.(float64)))
}

func (r *RemoteFile) GetModificationTime() time.Time {
	value, ok := r.Metadata["modificationTime"]
	if !ok {
		panic("modificationTime not found in metadata")
	}
	return time.UnixMicro(int64(value.(float64)))
}

func (r *RemoteFile) GetLatlong() *export.Location {
	if r.PublicMetadata != nil {
		// check if lat and long key exists
		if lat, ok := r.PublicMetadata["lat"]; ok {
			if long, ok := r.PublicMetadata["long"]; ok {
				if lat.(float64) == 0 && long.(float64) == 0 {
					return nil
				}
				return &export.Location{
					Latitude:  lat.(float64),
					Longitude: long.(float64),
				}
			}
		}
	}
	if lat, ok := r.Metadata["latitude"]; ok && lat != nil {
		if long, ok2 := r.Metadata["longitude"]; ok2 && long != nil {
			return &export.Location{
				Latitude:  lat.(float64),
				Longitude: long.(float64),
			}
		}
	}
	return nil
}
