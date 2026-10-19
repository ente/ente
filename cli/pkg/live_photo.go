package pkg

import (
	"archive/zip"
	"crypto/rand"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"regexp"

	"github.com/ente/cli/pkg/model"
)

const livePhotoExpansionRatio int64 = 20
const livePhotoExpansionOverhead int64 = 16 * 1024 * 1024

var livePhotoEntryName = regexp.MustCompile(`^(image|video)(\.[a-zA-Z0-9]{1,16})?$`)

func UnpackLive(src string) (imagePath, videoPath string, err error) {
	file, err := os.Open(src)
	if err != nil {
		return "", "", err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return "", "", err
	}
	archive, err := zip.NewReader(file, info.Size())
	if err != nil {
		return "", "", err
	}
	limit := min(info.Size(), (math.MaxInt64-livePhotoExpansionOverhead)/livePhotoExpansionRatio)*livePhotoExpansionRatio + livePhotoExpansionOverhead
	return unpackLive(archive, filepath.Dir(src), limit)
}

func unpackLive(archive *zip.Reader, dest string, limit int64) (imagePath, videoPath string, err error) {
	if len(archive.File) != 2 {
		return "", "", fmt.Errorf("%w: expected one image and one video", model.ErrLiveZip)
	}
	var image, video *zip.File
	declaredRemaining := uint64(limit)
	for _, file := range archive.File {
		match := livePhotoEntryName.FindStringSubmatch(file.Name)
		if match == nil || file.FileInfo().IsDir() {
			return "", "", fmt.Errorf("%w: invalid component name", model.ErrLiveZip)
		}
		if match[1] == "image" {
			image = file
		} else {
			video = file
		}
		if file.UncompressedSize64 > declaredRemaining {
			return "", "", fmt.Errorf("%w: archive expands beyond limit", model.ErrLiveZip)
		}
		declaredRemaining -= file.UncompressedSize64
	}
	if image == nil || video == nil {
		return "", "", fmt.Errorf("%w: expected one image and one video", model.ErrLiveZip)
	}

	var outputs []string
	defer func() {
		if err != nil {
			for _, path := range outputs {
				_ = os.Remove(path)
			}
			imagePath, videoPath = "", ""
		}
	}()
	remaining := limit
	for _, entry := range []*zip.File{image, video} {
		input, openErr := entry.Open()
		if openErr != nil {
			return "", "", openErr
		}
		path := filepath.Join(dest, "live-photo-"+rand.Text()+filepath.Ext(entry.Name))
		output, createErr := os.OpenFile(path, os.O_RDWR|os.O_CREATE|os.O_EXCL, 0666)
		if createErr != nil {
			input.Close()
			return "", "", createErr
		}
		outputs = append(outputs, output.Name())
		written, copyErr := copyLivePhotoComponent(output, input, remaining)
		input.Close()
		closeErr := output.Close()
		if copyErr != nil {
			return "", "", copyErr
		}
		if closeErr != nil {
			return "", "", closeErr
		}
		remaining -= written
	}
	return outputs[0], outputs[1], nil
}

func copyLivePhotoComponent(output io.Writer, input io.Reader, limit int64) (int64, error) {
	written, err := io.Copy(output, io.LimitReader(input, limit))
	if err != nil {
		return written, err
	}
	var extra [1]byte
	n, err := io.ReadFull(input, extra[:])
	if n != 0 {
		return written, fmt.Errorf("%w: archive expands beyond limit", model.ErrLiveZip)
	}
	if err == io.EOF {
		err = nil
	}
	return written, err
}
