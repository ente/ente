package userentity

import "testing"

func TestLibraryShareEntityValidation(t *testing.T) {
	validID := "ls_123_456"
	if err := (&EntityDataRequest{Type: LibraryShare, ID: &validID}).IsValid(123); err != nil {
		t.Fatalf("valid library share ID rejected: %v", err)
	}

	invalidID := "ls_124_456"
	if err := (&EntityDataRequest{Type: LibraryShare, ID: &invalidID}).IsValid(123); err == nil {
		t.Fatal("library share ID with a different owner accepted")
	}
}
