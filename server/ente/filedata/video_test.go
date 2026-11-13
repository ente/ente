package filedata

import (
	"errors"
	"math"
	"net/http"
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
			req := VidPreviewRequest{ObjectID: tc.id, ObjectSize: 1, Playlist: "playlist", PlayListHeader: "header"}
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

func TestVideoPreviewSize(t *testing.T) {
	for _, tc := range []struct {
		name     string
		original int64
		preview  int64
		allowed  bool
	}{
		{"smaller than original", 100_000_000, 50_000_000, true},
		{"small exactly 3x", 40_000_000, 120_000_000, true},
		{"small above 3x", 50_000_000, 190_000_000, true},
		{"small one byte below 4x", 40_000_000, 159_999_999, true},
		{"small exactly 4x", 40_000_000, 160_000_000, false},
		{"small above 4x", 40_000_000, 160_000_001, false},
		{"one byte below 200 MB", 60_000_000, 199_999_999, true},
		{"at 200 MB above 3x", 60_000_000, 200_000_000, false},
		{"at 200 MB below 3x", 70_000_000, 200_000_000, true},
		{"large exactly 3x", 100_000_000, 300_000_000, true},
		{"large one byte above 3x", 100_000_000, 300_000_001, false},
		{"large below 4x", 100_000_000, 350_000_000, false},
		{"one byte original at 3x", 1, 3, true},
		{"one byte original at 4x", 1, 4, false},
		{"missing original", 0, 1, false},
		{"negative original", -1, 1, false},
		{"zero preview", 1, 0, false},
		{"negative preview", 1, -1, false},
		{"largest original", math.MaxInt64, math.MaxInt64, true},
		{"3x would overflow", math.MaxInt64/3 + 1, math.MaxInt64, true},
		{"largest exact 3x", math.MaxInt64 / 3, math.MaxInt64 - 1, true},
		{"above largest exact 3x", math.MaxInt64 / 3, math.MaxInt64, false},
		{"4x would overflow", math.MaxInt64 / 4, math.MaxInt64, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			err := (VidPreviewRequest{ObjectSize: tc.preview}).ValidateSize(tc.original)
			if (err == nil) != tc.allowed {
				t.Fatalf("ValidateSize(%d) for preview %d = %v, allowed = %t", tc.original, tc.preview, err, tc.allowed)
			}
			if err != nil {
				var apiError *ente.ApiError
				if !errors.As(err, &apiError) || apiError.HttpStatusCode != http.StatusBadRequest {
					t.Fatalf("ValidateSize() error = %v, want HTTP 400", err)
				}
			}
		})
	}
}

func TestVideoPreviewRequestRejectsNonpositiveSize(t *testing.T) {
	for _, size := range []int64{0, -1} {
		err := (VidPreviewRequest{
			ObjectID: NewUploadID(ente.PreviewVideo), ObjectSize: size,
			Playlist: "playlist", PlayListHeader: "header",
		}).Validate()
		require.ErrorContains(t, err, "objectSize must be positive")
	}
}
