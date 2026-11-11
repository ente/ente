package public

import (
	"database/sql"
	"errors"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
)

func TestGetFileUrlRowByTokenReturnsActiveRow(t *testing.T) {
	repository, db := setupFileLinkRepositoryTest(t)

	insertFileLinkToken(t, db, "pft_disabled", "disabled-token", 1, 11, true)
	insertFileLinkToken(t, db, "pft_active", "active-token", 2, 22, false)

	row, err := repository.GetFileUrlRowByToken(t.Context(), "active-token")
	if err != nil {
		t.Fatalf("GetFileUrlRowByToken() error = %v", err)
	}
	if row.LinkID != "pft_active" || row.FileID != 2 || row.OwnerID != 22 || row.IsDisabled {
		t.Fatalf("expected active row, got %+v", row)
	}
}

func TestFileLinkInsertCanRetryWithNewTokenAfterCollision(t *testing.T) {
	repository, db := setupFileLinkRepositoryTest(t)
	insertFileLinkToken(t, db, "pft_disabled", "disabled-token", 1, 11, true)
	req := ente.CreateFileUrl{FileID: 2, App: ente.Photos}

	if _, err := repository.Insert(t.Context(), req, 22, "disabled-token"); !errors.Is(err, ente.ErrAccessTokenInUse) {
		t.Fatalf("expected retryable token collision, got %v", err)
	}
	id, err := repository.Insert(t.Context(), req, 22, "new-token")
	if err != nil {
		t.Fatalf("Insert() with a new token failed: %v", err)
	}
	row, err := repository.GetFileUrlRowByToken(t.Context(), "new-token")
	if err != nil {
		t.Fatalf("GetFileUrlRowByToken() error = %v", err)
	}
	if row.LinkID != *id || row.FileID != req.FileID || row.OwnerID != 22 || row.IsDisabled {
		t.Fatalf("expected newly created active link, got %+v", row)
	}
}

func TestGetFileUrlRowByTokenReturnsDisabledRowWhenNoActiveRowExists(t *testing.T) {
	repository, db := setupFileLinkRepositoryTest(t)

	insertFileLinkToken(t, db, "pft_disabled", "disabled-token", 1, 11, true)

	row, err := repository.GetFileUrlRowByToken(t.Context(), "disabled-token")
	if err != nil {
		t.Fatalf("GetFileUrlRowByToken() error = %v", err)
	}
	if row.LinkID != "pft_disabled" || !row.IsDisabled {
		t.Fatalf("expected disabled row, got %+v", row)
	}
}

func TestGetFileUrlRowByTokenReturnsNotFoundForUnknownToken(t *testing.T) {
	repository, _ := setupFileLinkRepositoryTest(t)

	_, err := repository.GetFileUrlRowByToken(t.Context(), "missing-token")
	if !errors.Is(err, ente.ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}
}

func TestDisableLinksForUserInvalidatesTheirCacheEntries(t *testing.T) {
	repository, db := setupFileLinkRepositoryTest(t)
	repository.Cache = NewLinkCache(time.Minute, time.Minute)

	insertFileLinkToken(t, db, "pft_owner_1", "owner-token-1", 1, 11, false)
	insertFileLinkToken(t, db, "pft_owner_2", "owner-token-2", 2, 11, false)
	insertFileLinkToken(t, db, "pft_other", "other-token", 3, 22, false)
	for _, token := range []string{"owner-token-1", "owner-token-2", "other-token"} {
		repository.Cache.Set(token, true, time.Now())
	}

	if err := repository.DisableLinksForUser(t.Context(), 11); err != nil {
		t.Fatalf("DisableLinksForUser() error = %v", err)
	}
	for _, token := range []string{"owner-token-1", "owner-token-2"} {
		if _, cached := repository.Cache.Get(token, token); cached {
			t.Fatalf("cache entry %q was not invalidated", token)
		}
	}
	if _, cached := repository.Cache.Get("other-token", "other-token"); !cached {
		t.Fatal("unaffected cache entry was invalidated")
	}
}

func setupFileLinkRepositoryTest(t *testing.T) (*FileLinkRepository, *sql.DB) {
	t.Helper()

	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	resetFileLinkTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
		resetFileLinkTables(t, db)
	})

	return NewFileLinkRepo(db), db
}

func resetFileLinkTables(t *testing.T, db *sql.DB) {
	t.Helper()

	_, err := db.Exec(`TRUNCATE TABLE public_file_tokens_access_history, public_file_tokens RESTART IDENTITY CASCADE`)
	if err != nil {
		t.Fatalf("failed to reset public file token tables: %v", err)
	}
}

func insertFileLinkToken(t *testing.T, db *sql.DB, id string, accessToken string, fileID int64, ownerID int64, isDisabled bool) {
	t.Helper()

	_, err := db.Exec(
		`INSERT INTO public_file_tokens(id, file_id, owner_id, app, access_token, is_disabled)
		 VALUES($1, $2, $3, $4, $5, $6)`,
		id,
		fileID,
		ownerID,
		"photos",
		accessToken,
		isDisabled,
	)
	if err != nil {
		t.Fatalf("failed to insert public file token %q: %v", id, err)
	}
}
