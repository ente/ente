package filedata

import (
	"testing"

	"github.com/ente/museum/ente"
	"github.com/stretchr/testify/require"
)

func TestVideoPreviewObjectID(t *testing.T) {
	const id = "pv_0123456789ABCDEFGHIJkl"
	for _, tc := range []struct {
		name  string
		id    string
		valid bool
	}{
		{"issued", NewUploadID(ente.PreviewVideo), true},
		{"mixed case and digits", id, true},
		{"short", id[:len(id)-1], false},
		{"long", id + "0", false},
		{"traversal", "../../../../2/file-data/2/vid_preview/" + id, false},
		{"slash", id[:len(id)-1] + "/", false},
		{"space", id[:len(id)-1] + " ", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			req := VidPreviewRequest{ObjectID: tc.id, Playlist: "playlist", PlayListHeader: "header"}
			err := req.Validate()
			if tc.valid {
				require.NoError(t, err)
			} else {
				var apiErr *ente.ApiError
				require.ErrorAs(t, err, &apiErr)
				require.Equal(t, ente.BadRequest, apiErr.Code)
			}
		})
	}
}
