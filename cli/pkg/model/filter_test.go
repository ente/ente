package model

import "testing"

func TestFilterExcludeByName(t *testing.T) {
	tests := []struct {
		name   string
		filter Filter
		album  RemoteAlbum
		want   bool
	}{
		{
			name:   "includes matching album without case or surrounding whitespace",
			filter: Filter{Albums: []string{"vacation"}},
			album:  RemoteAlbum{AlbumName: " Vacation "},
		},
		{
			name:   "excludes album absent from include list",
			filter: Filter{Albums: []string{"Vacation"}},
			album:  RemoteAlbum{AlbumName: "Work"},
			want:   true,
		},
		{
			name:   "excludes matching album without case or surrounding whitespace",
			filter: Filter{ExcludeAlbums: []string{"work"}},
			album:  RemoteAlbum{AlbumName: " Work "},
			want:   true,
		},
		{
			name: "exclude list takes precedence",
			filter: Filter{
				Albums:        []string{"Vacation"},
				ExcludeAlbums: []string{"Vacation"},
			},
			album: RemoteAlbum{AlbumName: "Vacation"},
			want:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.filter.excludeByName(tt.album); got != tt.want {
				t.Fatalf("excludeByName() = %v, want %v", got, tt.want)
			}
		})
	}
}
