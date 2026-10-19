package pkg

import (
	"archive/zip"
	"bytes"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/ente/cli/pkg/model"
)

func livePhotoArchive(t *testing.T, names []string, method uint16) []byte {
	t.Helper()
	var data bytes.Buffer
	writer := zip.NewWriter(&data)
	for _, name := range names {
		entry, err := writer.CreateHeader(&zip.FileHeader{Name: name, Method: method})
		if err != nil {
			t.Fatal(err)
		}
		if _, err := io.WriteString(entry, name); err != nil {
			t.Fatal(err)
		}
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	return data.Bytes()
}

func livePhotoReader(t *testing.T, data []byte) *zip.Reader {
	t.Helper()
	reader, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		t.Fatal(err)
	}
	return reader
}

func TestUnpackLive(t *testing.T) {
	for _, method := range []uint16{zip.Store, zip.Deflate} {
		for _, names := range [][]string{{"image.heic", "video.mov"}, {"video", "image"}} {
			root := t.TempDir()
			src := filepath.Join(root, "photo.zip")
			if err := os.WriteFile(src, livePhotoArchive(t, names, method), 0666); err != nil {
				t.Fatal(err)
			}
			sourceInfo, err := os.Stat(src)
			if err != nil {
				t.Fatal(err)
			}
			image, video, err := UnpackLive(src)
			if err != nil {
				t.Fatal(err)
			}
			for _, path := range []string{image, video} {
				info, err := os.Stat(path)
				if err != nil {
					t.Fatal(err)
				}
				if info.Mode().Perm() != sourceInfo.Mode().Perm() {
					t.Fatalf("component mode %o differs from normal export mode %o", info.Mode().Perm(), sourceInfo.Mode().Perm())
				}
				data, err := os.ReadFile(path)
				if err != nil {
					t.Fatal(err)
				}
				if string(data) != names[0] && string(data) != names[1] {
					t.Fatalf("unexpected component bytes: %q", data)
				}
				if filepath.Ext(path) != filepath.Ext(string(data)) {
					t.Fatalf("component extension changed: %s", path)
				}
			}
			data, _ := os.ReadFile(image)
			if !strings.HasPrefix(string(data), "image") {
				t.Fatalf("image and video swapped: %q", data)
			}
		}
	}
}

func TestUnpackLiveValidatesBeforeCreatingOutput(t *testing.T) {
	for _, names := range [][]string{
		{"image.jpg", "video.mov", "extra.txt"},
		{"image.jpg", "image.png"},
		{"folder/image.jpg", "video.mov"},
	} {
		root := t.TempDir()
		_, _, err := unpackLive(livePhotoReader(t, livePhotoArchive(t, names, zip.Store)), root, 1024)
		if !errors.Is(err, model.ErrLiveZip) {
			t.Fatalf("names %v: expected Live Photo error, got %v", names, err)
		}
		entries, _ := os.ReadDir(root)
		if len(entries) != 0 {
			t.Fatalf("invalid archive created output: %v", entries)
		}
	}
}

func TestUnpackLiveCombinedBudget(t *testing.T) {
	names := []string{"image.jpg", "video.mov"}
	size := int64(len(names[0]) + len(names[1]))
	for _, limit := range []int64{size - 1, size} {
		root := t.TempDir()
		_, _, err := unpackLive(livePhotoReader(t, livePhotoArchive(t, names, zip.Store)), root, limit)
		if limit == size && err != nil {
			t.Fatalf("exact budget rejected: %v", err)
		}
		if limit < size {
			if !errors.Is(err, model.ErrLiveZip) {
				t.Fatalf("expected budget error, got %v", err)
			}
			entries, _ := os.ReadDir(root)
			if len(entries) != 0 {
				t.Fatal("budget rejection created output")
			}
		}
	}
}

func TestCopyLivePhotoComponentBudget(t *testing.T) {
	for _, value := range []string{"", "hello", "hello!"} {
		var output bytes.Buffer
		written, err := copyLivePhotoComponent(&output, strings.NewReader(value), 5)
		if len(value) > 5 {
			if !errors.Is(err, model.ErrLiveZip) {
				t.Fatalf("expected budget error, got %v", err)
			}
		} else if err != nil {
			t.Fatal(err)
		}
		if written != int64(min(len(value), 5)) || output.String() != value[:written] {
			t.Fatalf("unexpected bounded output: %q (%d bytes)", output.String(), written)
		}
	}
}

type failedLivePhotoRead struct{}

func (failedLivePhotoRead) Read([]byte) (int, error) { return 0, io.ErrUnexpectedEOF }

func TestCopyLivePhotoComponentChecksErrorsAtBoundary(t *testing.T) {
	input := io.MultiReader(strings.NewReader("hello"), failedLivePhotoRead{})
	written, err := copyLivePhotoComponent(io.Discard, input, 5)
	if written != 5 || !errors.Is(err, io.ErrUnexpectedEOF) {
		t.Fatalf("expected read failure at the exact boundary, got %d, %v", written, err)
	}
}

func TestUnpackLiveCleansUpFailedExtraction(t *testing.T) {
	root := t.TempDir()
	sentinel := filepath.Join(root, "image.jpg")
	if err := os.WriteFile(sentinel, []byte("existing"), 0600); err != nil {
		t.Fatal(err)
	}
	archive := livePhotoReader(t, livePhotoArchive(t, []string{"image.jpg", "video.mov"}, zip.Store))
	opened := 0
	archive.RegisterDecompressor(zip.Store, func(input io.Reader) io.ReadCloser {
		opened++
		if opened == 2 {
			return io.NopCloser(io.MultiReader(io.LimitReader(input, 1), failedLivePhotoRead{}))
		}
		return io.NopCloser(input)
	})
	image, video, err := unpackLive(archive, root, 1024)
	if !errors.Is(err, io.ErrUnexpectedEOF) || image != "" || video != "" {
		t.Fatalf("unexpected failed extraction result: %q %q %v", image, video, err)
	}
	entries, _ := os.ReadDir(root)
	if len(entries) != 1 || entries[0].Name() != "image.jpg" {
		t.Fatalf("partial components remain: %v", entries)
	}
	data, _ := os.ReadFile(sentinel)
	if string(data) != "existing" {
		t.Fatal("existing file changed")
	}
}
