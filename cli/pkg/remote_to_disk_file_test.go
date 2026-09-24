package pkg

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/ente/cli/pkg/model"
	"github.com/ente/cli/pkg/model/export"
)

const (
	testAlbumID  = int64(7)
	testFileID   = int64(42)
	testFileName = "photo.jpg"
)

// writeExportedAlbum recreates under root what an export leaves behind for a
// single photo: the album folder, its .meta folder with the album metadata and
// optionally the per file metadata and the media file itself.
func writeExportedAlbum(t *testing.T, root string, withFileMetadata, withMedia bool) *export.AlbumMetadata {
	t.Helper()
	albumMeta := &export.AlbumMetadata{ID: testAlbumID, AlbumName: "Trip", FolderName: "Trip"}
	albumPath := filepath.Join(root, albumMeta.FolderName)
	metaPath := filepath.Join(albumPath, albumMetaFolder)
	if err := os.MkdirAll(metaPath, 0755); err != nil {
		t.Fatal(err)
	}
	if err := writeJSONToFile(filepath.Join(metaPath, albumMetaFile), albumMeta); err != nil {
		t.Fatal(err)
	}
	if withFileMetadata {
		fileMetadata := export.DiskFileMetadata{Title: testFileName, Info: &export.Info{ID: testFileID}}
		fileMetadata.AddFileName(testFileName)
		if err := writeJSONToFile(filepath.Join(metaPath, testFileName+".json"), &fileMetadata); err != nil {
			t.Fatal(err)
		}
	}
	if withMedia {
		if err := os.WriteFile(filepath.Join(albumPath, testFileName), []byte("media"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	return albumMeta
}

func TestNeedsDownloadAfterExportDirChange(t *testing.T) {
	previousRoot := t.TempDir()
	previousAlbumMeta := writeExportedAlbum(t, previousRoot, true, true)

	// The new export root only gets the album folders, their .meta folders and
	// the metadata files; the media files are missing.
	newRoot := t.TempDir()
	newAlbumMeta := writeExportedAlbum(t, newRoot, false, false)

	entry := &model.AlbumFileEntry{AlbumID: testAlbumID, FileID: testFileID, SyncedLocally: true}

	previousDiskInfo, err := readFilesMetadata(previousRoot, previousAlbumMeta)
	if err != nil {
		t.Fatal(err)
	}
	if needsDownload(entry, previousDiskInfo) {
		t.Fatal("file exported into the current root must not be downloaded again")
	}

	newDiskInfo, err := readFilesMetadata(newRoot, newAlbumMeta)
	if err != nil {
		t.Fatal(err)
	}
	if !needsDownload(entry, newDiskInfo) {
		t.Fatal("file missing from the new export root must be downloaded")
	}
}

func TestNeedsDownloadChecksDiskNotRecordedState(t *testing.T) {
	tests := []struct {
		name             string
		withFileMetadata bool
		withMedia        bool
		syncedLocally    bool
		want             bool
	}{
		{name: "media file present", withFileMetadata: true, withMedia: true, syncedLocally: true, want: false},
		{name: "metadata without media file", withFileMetadata: true, syncedLocally: true, want: true},
		{name: "media file without metadata", withMedia: true, syncedLocally: true, want: true},
		{name: "entry not marked as synced", withFileMetadata: true, withMedia: true, syncedLocally: false, want: true},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			root := t.TempDir()
			albumMeta := writeExportedAlbum(t, root, test.withFileMetadata, test.withMedia)
			diskInfo, err := readFilesMetadata(root, albumMeta)
			if err != nil {
				t.Fatal(err)
			}
			entry := &model.AlbumFileEntry{AlbumID: testAlbumID, FileID: testFileID, SyncedLocally: test.syncedLocally}
			if got := needsDownload(entry, diskInfo); got != test.want {
				t.Fatalf("needsDownload() = %v, want %v", got, test.want)
			}
		})
	}
}
