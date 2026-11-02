package filedata

import (
	"regexp"

	"github.com/ente/museum/ente"
)

var videoPreviewObjectIDPattern = regexp.MustCompile(`^pv_[0-9A-Za-z]{22}$`)

type VidPreviewRequest struct {
	FileID         int64  `json:"fileID" binding:"required"`
	ObjectID       string `json:"objectID" binding:"required"`
	ObjectSize     int64  `json:"objectSize" binding:"required"`
	Playlist       string `json:"playlist" binding:"required"`
	PlayListHeader string `json:"playlistHeader" binding:"required"`
	Version        *int   `json:"version"`
}

func (r VidPreviewRequest) Validate() error {
	if r.Playlist == "" || r.PlayListHeader == "" {
		return ente.NewBadRequestWithMessage("playlist and playListHeader are required for preview video")
	}
	if !videoPreviewObjectIDPattern.MatchString(r.ObjectID) {
		return ente.NewBadRequestWithMessage("invalid video preview object ID")
	}
	return nil
}
