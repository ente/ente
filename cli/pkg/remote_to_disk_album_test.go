package pkg

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSanitizeAlbumFolderName(t *testing.T) {
	tests := []struct {
		name string
		want string
	}{
		{`Trip/2026\Raw`, "Trip_2026_Raw"},
		{`A<B>C:D"E|F?G*H`, "A_B_C_D_E_F_G_H"},
		{"A\x00B\x1fC", "A_B_C"},
		{"Album. ", "Album"},
		{"..", "_"},
		{"COM9.backup", "_COM9.backup"},
		{"LPT³.json", "_LPT³.json"},
		{"NUL .txt", "_NUL .txt"},
		{"COM10", "COM10"},
		{".CON", ".CON"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := sanitizeAlbumFolderName(test.name); got != test.want {
				t.Fatalf("sanitizeAlbumFolderName(%q) = %q, want %q", test.name, got, test.want)
			}
		})
	}
}

func TestUniqueAlbumFolderNameUsesFilesystemCollisions(t *testing.T) {
	root := t.TempDir()
	for _, name := range []string{"Album", "album_1"} {
		if err := os.WriteFile(filepath.Join(root, name), nil, 0600); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := os.Lstat(filepath.Join(root, "album")); os.IsNotExist(err) {
		if err := os.WriteFile(filepath.Join(root, "album"), nil, 0600); err != nil {
			t.Fatal(err)
		}
	}

	got, err := uniqueAlbumFolderName(root, "album")
	if err != nil {
		t.Fatal(err)
	}
	if got != "album_2" {
		t.Fatalf("uniqueAlbumFolderName() = %q, want %q", got, "album_2")
	}
}
