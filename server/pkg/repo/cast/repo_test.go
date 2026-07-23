package cast

import (
	"database/sql"
	"testing"

	"github.com/ente/museum/internal/testutil"
	"github.com/google/uuid"
)

func TestRevokeForGivenDeviceIDOnlyDeletesUserDevice(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})
	repository := &Repository{DB: db}
	deviceID := uuid.New()
	ownerID := int64(1)
	otherUserID := int64(2)
	_, err := db.Exec(
		`INSERT INTO casting (id, code, public_key, cast_user, ip) VALUES ($1, $2, $3, $4, $5)`,
		deviceID,
		"ABC123",
		"public-key",
		ownerID,
		"127.0.0.1",
	)
	if err != nil {
		t.Fatalf("failed to insert casting row: %v", err)
	}
	if err := repository.RevokeForGivenUserAndDevice(t.Context(), otherUserID, deviceID); err != nil {
		t.Fatalf("RevokeForGivenDeviceID other user error = %v", err)
	}
	if isDeleted := getCastDeviceIsDeleted(t, db, deviceID); isDeleted {
		t.Fatal("other user should not delete device")
	}
	if err := repository.RevokeForGivenUserAndDevice(t.Context(), ownerID, deviceID); err != nil {
		t.Fatalf("RevokeForGivenDeviceID owner error = %v", err)
	}
	if isDeleted := getCastDeviceIsDeleted(t, db, deviceID); !isDeleted {
		t.Fatal("owner should delete device")
	}
}

func getCastDeviceIsDeleted(t *testing.T, db *sql.DB, deviceID uuid.UUID) bool {
	t.Helper()
	var isDeleted bool
	err := db.QueryRow(`SELECT is_deleted FROM casting WHERE id = $1`, deviceID).Scan(&isDeleted)
	if err != nil {
		t.Fatalf("failed to get casting row: %v", err)
	}
	return isDeleted
}
