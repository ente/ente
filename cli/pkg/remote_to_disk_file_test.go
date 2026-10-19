package pkg

import (
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"testing"

	"github.com/ente/cli/pkg/model"
	"github.com/ente/cli/pkg/model/export"
)

func TestRemoveDiskFile(t *testing.T) {
	tests := []struct {
		name      string
		fileNames []string
		wantErr   bool
	}{
		{"photo", []string{"photo.jpg"}, false},
		{"live photo", []string{"photo.jpg", "video.mov"}, false},
		{"missing media", []string{"missing.jpg"}, false},
		{"empty list", nil, false},
		{"unicode and spaces", []string{"夏 2026.jpg"}, false},
		{"dotfile", []string{".photo.jpg"}, false},
		{"parent traversal", []string{"photo.jpg", "../outside.jpg"}, true},
		{"nested path", []string{"photo.jpg", "sub/photo.jpg"}, true},
		{"cleaned path", []string{"photo.jpg", "sub/../photo.jpg"}, true},
		{"empty name", []string{"photo.jpg", ""}, true},
		{"dot", []string{"photo.jpg", "."}, true},
		{"parent", []string{"photo.jpg", ".."}, true},
		{"absolute path", []string{"photo.jpg", filepath.Join(t.TempDir(), "outside.jpg")}, true},
		{"backslash", []string{`photo\name.jpg`}, runtime.GOOS == "windows"},
		{"colon", []string{"photo:name.jpg"}, runtime.GOOS == "windows"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			root := t.TempDir()
			albumPath := filepath.Join(root, "Album")
			if err := os.MkdirAll(filepath.Join(albumPath, albumMetaFolder), 0700); err != nil {
				t.Fatal(err)
			}
			media := []string{"photo.jpg", "video.mov", "夏 2026.jpg", ".photo.jpg", "unrelated.jpg"}
			if runtime.GOOS != "windows" {
				media = append(media, `photo\name.jpg`, "photo:name.jpg")
			}
			for _, name := range media {
				if err := os.WriteFile(filepath.Join(albumPath, name), []byte("photo"), 0600); err != nil {
					t.Fatal(err)
				}
			}
			const metaFile = "photo.json"
			metaPath := filepath.Join(albumPath, albumMetaFolder, metaFile)
			metadata := export.DiskFileMetadata{Info: &export.Info{ID: 1, FileNames: test.fileNames}}
			if err := writeJSONToFile(metaPath, &metadata); err != nil {
				t.Fatal(err)
			}
			disk, err := readFilesMetadata(root, &export.AlbumMetadata{FolderName: "Album"})
			if err != nil {
				t.Fatal(err)
			}
			file := model.RemoteFile{ID: 1}
			err = removeDiskFile(disk.GetDiskFileMetadata(file), disk)
			if (err != nil) != test.wantErr {
				t.Fatalf("removeDiskFile() = %v, want error %v", err, test.wantErr)
			}
			if disk.IsFilePresent(file) != test.wantErr || disk.IsMetaFileNamePresent(metaFile) != test.wantErr {
				t.Fatal("unexpected metadata index state")
			}
			for _, name := range append(media, filepath.Join(albumMetaFolder, metaFile)) {
				wantPresent := test.wantErr || (name != filepath.Join(albumMetaFolder, metaFile) && !slices.Contains(test.fileNames, name))
				_, err := os.Stat(filepath.Join(albumPath, name))
				if wantPresent && err != nil || !wantPresent && !os.IsNotExist(err) {
					t.Errorf("file %q: stat error %v, want present %v", name, err, wantPresent)
				}
			}
		})
	}
}
