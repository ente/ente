package pkg

import (
	"archive/zip"
	"bytes"
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/ente/cli/internal/crypto"
	"github.com/ente/cli/pkg/model"
	"github.com/ente/cli/pkg/model/export"
	"github.com/ente/cli/pkg/secrets"
	"github.com/ente/cli/utils/encoding"
	bolt "go.etcd.io/bbolt"
)

const tempCleanupAccountKey = "temp-cleanup-test"

// tempCleanupCtrl returns a controller whose temp folder is a fresh directory
// under ENTE_CLI_TMP_PATH, the way a syncing run sets it up.
func tempCleanupCtrl(t *testing.T) (*ClICtrl, []byte) {
	t.Helper()
	tempRoot := t.TempDir()
	t.Setenv("ENTE_CLI_TMP_PATH", tempRoot)
	deviceKey := bytes.Repeat([]byte{0x11}, 32)
	db, err := bolt.Open(filepath.Join(t.TempDir(), "cli.db"), 0600, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })
	ctrl := &ClICtrl{DB: db, KeyHolder: secrets.NewKeyHolder(deviceKey)}
	if err := ctrl.Init(); err != nil {
		t.Fatal(err)
	}
	if want := filepath.Join(tempRoot, "ente-download"); ctrl.tempFolder != want {
		t.Fatalf("temp folder = %q, want %q", ctrl.tempFolder, want)
	}
	if err := db.Update(func(tx *bolt.Tx) error {
		account, err := tx.CreateBucketIfNotExists([]byte(tempCleanupAccountKey))
		if err != nil {
			return err
		}
		_, err = account.CreateBucketIfNotExists([]byte(model.RemoteAlbumEntries))
		return err
	}); err != nil {
		t.Fatal(err)
	}
	return ctrl, deviceKey
}

// seedTempDownload writes the encrypted form of content into the temp folder,
// as a completed download does, and returns the file nonce and the size of the
// encrypted file. Keeping file.Info.FileSize in sync with it keeps the entry
// off the network.
func seedTempDownload(t *testing.T, ctrl *ClICtrl, fileID int64, content, encryptionKey []byte) (string, int64) {
	t.Helper()
	encrypted, nonce, err := crypto.EncryptChaCha20poly1305(content, encryptionKey)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(ctrl.tempPath(fileID, ""), encrypted, 0600); err != nil {
		t.Fatal(err)
	}
	return encoding.EncodeBase64(nonce), int64(len(encrypted))
}

func livePhotoZip(t *testing.T, names ...string) []byte {
	t.Helper()
	var buffer bytes.Buffer
	writer := zip.NewWriter(&buffer)
	for _, name := range names {
		entry, err := writer.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := entry.Write([]byte(name)); err != nil {
			t.Fatal(err)
		}
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	return buffer.Bytes()
}

func testRemoteFile(fileID int64, title string, fileType model.FileType, fileKey, deviceKey []byte, fileNonce string, fileSize int64) model.RemoteFile {
	return model.RemoteFile{
		ID:        fileID,
		Key:       *model.MakeEncString(fileKey, deviceKey),
		FileNonce: fileNonce,
		Info:      model.Info{FileSize: fileSize},
		Metadata: map[string]interface{}{
			"fileType":         float64(fileType),
			"title":            title,
			"creationTime":     float64(1700000000000000),
			"modificationTime": float64(1700000000000000),
		},
	}
}

// assertTempFolderEmpty fails if any artifact survived the entry, whether it
// was exported or not. A leaking entry is what fills up the temp filesystem
// (/tmp) until exports fail with "no space left on device" (#6551).
func assertTempFolderEmpty(t *testing.T, ctrl *ClICtrl) {
	t.Helper()
	entries, err := os.ReadDir(ctrl.tempFolder)
	if err != nil {
		t.Fatal(err)
	}
	names := make([]string, 0, len(entries))
	for _, entry := range entries {
		names = append(names, entry.Name())
	}
	if len(names) != 0 {
		t.Fatalf("temp folder %s is not empty: %v", ctrl.tempFolder, names)
	}
}

func TestDownloadEntryRemovesTempArtifacts(t *testing.T) {
	const fileID = 42
	const title = "photo.jpg"

	tests := []struct {
		name              string
		livePhoto         bool
		unexpectedZipFile bool
		corruptKey        bool
		missingAlbumDir   bool
		wantExportFiles   []string
		wantErr           bool
	}{
		{
			name:            "image export",
			wantExportFiles: []string{"photo.jpg"},
		},
		{
			name:            "live photo export",
			livePhoto:       true,
			wantExportFiles: []string{"photo.jpg", "photo.mov"},
		},
		{
			name:       "failed decryption",
			corruptKey: true,
			wantErr:    true,
		},
		{
			name:            "failed move",
			missingAlbumDir: true,
			wantErr:         true,
		},
		{
			name:              "failed live photo unpack",
			livePhoto:         true,
			unexpectedZipFile: true,
			wantErr:           true,
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			ctrl, deviceKey := tempCleanupCtrl(t)
			exportRoot := t.TempDir()
			albumFolder := filepath.Join(exportRoot, "Album")
			if err := os.MkdirAll(filepath.Join(albumFolder, albumMetaFolder), 0755); err != nil {
				t.Fatal(err)
			}
			if test.missingAlbumDir {
				if err := os.RemoveAll(albumFolder); err != nil {
					t.Fatal(err)
				}
			}

			fileType := model.Image
			content := []byte("photo bytes")
			if test.livePhoto {
				fileType = model.LivePhoto
				names := []string{"image.jpg", "video.mov"}
				if test.unexpectedZipFile {
					names = append(names, "notes.txt")
				}
				content = livePhotoZip(t, names...)
			}
			encryptionKey := bytes.Repeat([]byte{0x22}, 32)
			fileKey := encryptionKey
			if test.corruptKey {
				// Encrypt with a key the file does not carry, so decryption fails.
				fileKey = bytes.Repeat([]byte{0x33}, 32)
			}
			fileNonce, fileSize := seedTempDownload(t, ctrl, fileID, content, encryptionKey)
			file := testRemoteFile(fileID, title, fileType, fileKey, deviceKey, fileNonce, fileSize)

			diskInfo := &albumDiskInfo{
				ExportRoot:                exportRoot,
				AlbumMeta:                 &export.AlbumMetadata{ID: 1, AlbumName: "Album", FolderName: "Album"},
				FileNames:                 &map[string]bool{},
				MetaFileNameToDiskFileMap: &map[string]*export.DiskFileMetadata{},
				FileIdToDiskFileMap:       &map[int64]*export.DiskFileMetadata{},
			}
			ctx := context.WithValue(context.Background(), "account_key", tempCleanupAccountKey)
			err := ctrl.downloadEntry(ctx, diskInfo, file, &model.AlbumFileEntry{FileID: fileID, AlbumID: 1})
			if (err != nil) != test.wantErr {
				t.Fatalf("downloadEntry() error = %v, wantErr = %v", err, test.wantErr)
			}
			assertTempFolderEmpty(t, ctrl)
			for _, name := range test.wantExportFiles {
				if _, err := os.Stat(filepath.Join(albumFolder, name)); err != nil {
					t.Errorf("exported file %s: %v", name, err)
				}
			}
			if !test.wantErr && !diskInfo.IsFilePresent(file) {
				t.Errorf("exported entry is missing from the album metadata")
			}
		})
	}
}
