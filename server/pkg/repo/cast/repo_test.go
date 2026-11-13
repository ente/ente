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

func TestInsertCastDataReturnsDeviceID(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})
	repository := &Repository{DB: db}
	deviceID := uuid.New()
	_, err := db.Exec(
		`INSERT INTO casting (id, code, public_key, ip) VALUES ($1, $2, $3, $4)`,
		deviceID,
		"ABC123",
		"public-key",
		"127.0.0.1",
	)
	if err != nil {
		t.Fatalf("failed to insert casting row: %v", err)
	}

	gotDeviceID, err := repository.InsertCastData(
		t.Context(),
		1,
		"abc123",
		42,
		"cast-token",
		"encrypted-payload",
	)
	if err != nil {
		t.Fatalf("InsertCastData() error = %v", err)
	}
	if gotDeviceID != deviceID {
		t.Fatalf("InsertCastData() device ID = %s, want %s", gotDeviceID, deviceID)
	}
}

func TestGetDeviceInfo(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})
	repository := &Repository{DB: db}
	_, err := db.Exec(
		`INSERT INTO casting (id, code, public_key, pq_public_key, ip) VALUES ($1, $2, $3, $4, $5)`,
		uuid.New(),
		"ABC123",
		"public-key",
		"pq-public-key",
		"127.0.0.1",
	)
	if err != nil {
		t.Fatalf("failed to insert casting row: %v", err)
	}

	info, ip, err := repository.GetDeviceInfoAndIP(t.Context(), "abc123")
	if err != nil {
		t.Fatalf("GetDeviceInfoAndIP() error = %v", err)
	}
	if info.PublicKey != "public-key" || info.PQPublicKey == nil || *info.PQPublicKey != "pq-public-key" {
		t.Fatalf("GetDeviceInfoAndIP() info = %+v", info)
	}
	if ip != "127.0.0.1" {
		t.Fatalf("GetDeviceInfoAndIP() IP = %q", ip)
	}

	_, err = db.Exec(
		`INSERT INTO casting (id, code, public_key, ip) VALUES ($1, $2, $3, $4)`,
		uuid.New(),
		"DEF456",
		"classical-only",
		"127.0.0.2",
	)
	if err != nil {
		t.Fatalf("failed to insert classical casting row: %v", err)
	}
	info, _, err = repository.GetDeviceInfoAndIP(t.Context(), "DEF456")
	if err != nil {
		t.Fatalf("GetDeviceInfoAndIP() classical error = %v", err)
	}
	if info.PQPublicKey != nil {
		t.Fatalf("GetDeviceInfoAndIP() PQ public key = %q", *info.PQPublicKey)
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
