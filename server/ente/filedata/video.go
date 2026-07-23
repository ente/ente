package filedata

import "github.com/ente/museum/ente"

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
	return nil
}
