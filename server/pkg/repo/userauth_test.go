package repo

import (
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/utils/time"
)

func TestUserAuthRepositoryRemoveOTTReturnsWhetherRowWasConsumed(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	if _, err := db.Exec(`TRUNCATE TABLE otts RESTART IDENTITY CASCADE`); err != nil {
		t.Fatalf("failed to reset otts: %v", err)
	}
	t.Cleanup(func() {
		if _, err := db.Exec(`TRUNCATE TABLE otts RESTART IDENTITY CASCADE`); err != nil {
			t.Errorf("failed to reset otts: %v", err)
		}
	})

	repo := &UserAuthRepository{DB: db}
	emailHash := "duplicate-verify-email-hash"
	ott := "123456"
	app := ente.Photos

	err := repo.AddOTT(emailHash, app, ott, time.Microseconds()+60*1000000)
	if err != nil {
		t.Fatalf("failed to add ott: %v", err)
	}

	removed, err := repo.RemoveOTT(emailHash, ott, app)
	if err != nil {
		t.Fatalf("first remove returned error: %v", err)
	}
	if !removed {
		t.Fatal("first remove should consume the ott")
	}

	removed, err = repo.RemoveOTT(emailHash, ott, app)
	if err != nil {
		t.Fatalf("second remove returned error: %v", err)
	}
	if removed {
		t.Fatal("second remove should report that the ott was already consumed")
	}
}
