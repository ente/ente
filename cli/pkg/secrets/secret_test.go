package secrets

import (
	"bytes"
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func TestGetSecretFromSecretTextCreatesPrivateFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "secret.txt")

	want := GetSecretFromSecretText(path)
	if len(want) != keyLength {
		t.Fatalf("secret length = %d, want %d", len(want), keyLength)
	}

	if runtime.GOOS != "windows" {
		info, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		if got := info.Mode().Perm(); got != 0600 {
			t.Fatalf("secret file mode = %04o, want 0600", got)
		}
	}

	if got := GetSecretFromSecretText(path); !bytes.Equal(got, want) {
		t.Fatal("reading the secret again returned different bytes")
	}
}

func TestGetSecretFromSecretTextPreservesExistingFileMode(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Windows does not preserve POSIX file modes")
	}

	path := filepath.Join(t.TempDir(), "secret.txt")
	want := bytes.Repeat([]byte{1}, keyLength)
	if err := os.WriteFile(path, want, 0400); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, 0400); err != nil {
		t.Fatal(err)
	}

	got := GetSecretFromSecretText(path)
	if !bytes.Equal(got, want) {
		t.Fatal("existing secret changed")
	}

	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if got := info.Mode().Perm(); got != 0400 {
		t.Fatalf("existing secret file mode = %04o, want 0400", got)
	}
}

func TestCreateSecretFileDoesNotOverwriteExistingFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "secret.txt")
	want := bytes.Repeat([]byte{1}, keyLength)
	if err := os.WriteFile(path, want, 0644); err != nil {
		t.Fatal(err)
	}
	if runtime.GOOS != "windows" {
		if err := os.Chmod(path, 0644); err != nil {
			t.Fatal(err)
		}
	}

	err := createSecretFile(path, bytes.Repeat([]byte{2}, keyLength))
	if !os.IsExist(err) {
		t.Fatalf("createSecretFile() error = %v, want file-exists error", err)
	}

	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, want) {
		t.Fatal("existing secret was overwritten")
	}

	if runtime.GOOS != "windows" {
		info, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		if got := info.Mode().Perm(); got != 0644 {
			t.Fatalf("existing secret file mode = %04o, want 0644", got)
		}
	}
}
