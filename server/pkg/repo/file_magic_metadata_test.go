package repo

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestUpdateMagicAttributesValidatesAgainstStoredMetadata(t *testing.T) {
	stored := ente.MagicMetadata{Version: 3, Count: 4, Data: "stored", Header: "header"}
	for _, tc := range []struct {
		name     string
		isPublic bool
		asOther  bool
		update   ente.MagicMetadata
		wantErr  error
	}{
		{name: "private", update: ente.MagicMetadata{Version: 3, Count: 2, Data: "new", Header: "header"}},
		{name: "public", isPublic: true, update: ente.MagicMetadata{Version: 3, Count: 5, Data: "new", Header: "header"}},
		{name: "not owner", asOther: true, update: ente.MagicMetadata{Version: 3, Count: 4, Data: "new", Header: "header"}, wantErr: ente.ErrPermissionDenied},
		{name: "stale version", update: ente.MagicMetadata{Version: 2, Count: 4, Data: "new", Header: "header"}, wantErr: ente.ErrVersionMismatch},
		{name: "count drop", update: ente.MagicMetadata{Version: 3, Count: 1, Data: "new", Header: "header"}, wantErr: ente.ErrVersionMismatch},
	} {
		t.Run(tc.name, func(t *testing.T) {
			db, repository, ownerID, fileID := setupMagicMetadataTest(t, stored, tc.isPublic)
			userID := ownerID
			if tc.asOther {
				userID = testutil.InsertUser(t, db, testutil.UserFixture{UserID: 2, Email: "other@example.com", CreationTime: 1})
			}

			err := repository.UpdateMagicAttributes(t.Context(), userID,
				[]ente.UpdateMagicMetadata{{ID: fileID, MagicMetadata: tc.update}}, tc.isPublic, nil)

			if tc.wantErr != nil {
				require.ErrorIs(t, err, tc.wantErr)
				require.Equal(t, stored, readMagicMetadata(t, db, fileID, tc.isPublic))
				return
			}
			require.NoError(t, err)
			want := tc.update
			want.Version = 4
			require.Equal(t, want, readMagicMetadata(t, db, fileID, tc.isPublic))
		})
	}
}

func TestUpdateMagicAttributesAppliesBatchAtomically(t *testing.T) {
	stored := ente.MagicMetadata{Version: 1, Count: 1, Data: "stored", Header: "header"}
	db, repository, ownerID, firstID := setupMagicMetadataTest(t, stored, false)
	secondID := insertObjectTestFile(t, db, ownerID)
	update := func(id int64, data string) ente.UpdateMagicMetadata {
		return ente.UpdateMagicMetadata{ID: id, MagicMetadata: ente.MagicMetadata{Version: 1, Count: 1, Data: data, Header: "header"}}
	}

	err := repository.UpdateMagicAttributes(t.Context(), ownerID,
		[]ente.UpdateMagicMetadata{update(firstID, "first"), update(secondID+1000, "missing")}, false, nil)
	require.ErrorIs(t, err, sql.ErrNoRows)
	require.Equal(t, stored, readMagicMetadata(t, db, firstID, false))

	require.NoError(t, repository.UpdateMagicAttributes(t.Context(), ownerID,
		[]ente.UpdateMagicMetadata{update(firstID, "first"), update(secondID, "second"), update(firstID, "last")}, false, nil))
	require.Equal(t, ente.MagicMetadata{Version: 2, Count: 1, Data: "last", Header: "header"}, readMagicMetadata(t, db, firstID, false))
	require.Equal(t, ente.MagicMetadata{Version: 2, Count: 1, Data: "second", Header: "header"}, readMagicMetadata(t, db, secondID, false))
	require.Greater(t, readMembershipTime(t, db, firstID), int64(1))
}

func TestUpdateMagicAttributesRejectsVersionChangedWhileWaitingForLock(t *testing.T) {
	stored := ente.MagicMetadata{Version: 1, Count: 1, Data: "stored", Header: "header"}
	db, repository, ownerID, fileID := setupMagicMetadataTest(t, stored, false)
	concurrent := ente.MagicMetadata{Version: 2, Count: 1, Data: "concurrent", Header: "header"}
	blocker, blockerPID := beginFileBlocker(t, db, `UPDATE files SET magic_metadata = $2 WHERE file_id = $1`, fileID, concurrent)

	result := make(chan error, 1)
	go func() {
		result <- repository.UpdateMagicAttributes(t.Context(), ownerID, []ente.UpdateMagicMetadata{{
			ID: fileID, MagicMetadata: ente.MagicMetadata{Version: 1, Count: 1, Data: "mine", Header: "header"},
		}}, false, nil)
	}()
	waitUntilBlockedBy(t, db, blockerPID)
	require.NoError(t, blocker.Commit())

	require.ErrorIs(t, <-result, ente.ErrVersionMismatch)
	require.Equal(t, concurrent, readMagicMetadata(t, db, fileID, false))
}

func TestUpdateMagicAttributesTimestampsAfterWaitingForLock(t *testing.T) {
	stored := ente.MagicMetadata{Version: 1, Count: 1, Data: "stored", Header: "header"}
	db, repository, ownerID, queuedID := setupMagicMetadataTest(t, stored, false)
	var collectionID int64
	require.NoError(t, db.QueryRow(`SELECT collection_id FROM collection_files WHERE file_id = $1`, queuedID).Scan(&collectionID))
	otherID := insertObjectTestFile(t, db, ownerID)
	linkObjectTestFileToCollection(t, db, collectionID, otherID, ownerID)
	update := func(id int64) []ente.UpdateMagicMetadata {
		return []ente.UpdateMagicMetadata{{ID: id, MagicMetadata: ente.MagicMetadata{Version: 1, Count: 1, Data: "new", Header: "header"}}}
	}
	blocker, blockerPID := beginFileBlocker(t, db, `SELECT file_id FROM files WHERE file_id = $1 FOR UPDATE`, queuedID)

	result := make(chan error, 1)
	go func() { result <- repository.UpdateMagicAttributes(t.Context(), ownerID, update(queuedID), false, nil) }()
	waitUntilBlockedBy(t, db, blockerPID)
	require.NoError(t, repository.UpdateMagicAttributes(t.Context(), ownerID, update(otherID), false, nil))
	cursor := readMembershipTime(t, db, otherID)
	require.NoError(t, blocker.Commit())

	require.NoError(t, <-result)
	require.Greater(t, readMembershipTime(t, db, queuedID), cursor)
}

func TestUpdateMagicAttributesDoesNotLockOtherOwnersFiles(t *testing.T) {
	stored := ente.MagicMetadata{Version: 1, Count: 1, Data: "stored", Header: "header"}
	db, repository, _, fileID := setupMagicMetadataTest(t, stored, false)
	otherUserID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 2, Email: "other@example.com", CreationTime: 1})
	blocker, _ := beginFileBlocker(t, db, `SELECT file_id FROM files WHERE file_id = $1 FOR UPDATE`, fileID)
	defer blocker.Rollback()

	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	err := repository.UpdateMagicAttributes(ctx, otherUserID, []ente.UpdateMagicMetadata{{
		ID: fileID, MagicMetadata: ente.MagicMetadata{Version: 1, Count: 1, Data: "new", Header: "header"},
	}}, false, nil)

	require.ErrorIs(t, err, ente.ErrPermissionDenied)
}

func beginFileBlocker(t *testing.T, db *sql.DB, query string, args ...any) (*sql.Tx, int) {
	t.Helper()
	blocker, err := db.BeginTx(t.Context(), nil)
	require.NoError(t, err)
	t.Cleanup(func() { _ = blocker.Rollback() })
	var pid int
	require.NoError(t, blocker.QueryRowContext(t.Context(), `SELECT pg_backend_pid()`).Scan(&pid))
	_, err = blocker.ExecContext(t.Context(), query, args...)
	require.NoError(t, err)
	return blocker, pid
}

func waitUntilBlockedBy(t *testing.T, db *sql.DB, pid int) {
	t.Helper()
	require.EventuallyWithT(t, func(collect *assert.CollectT) {
		var blocked bool
		require.NoError(collect, db.QueryRow(`SELECT EXISTS(SELECT 1 FROM pg_stat_activity
			WHERE datname = current_database() AND $1 = ANY(pg_blocking_pids(pid)))`, pid).Scan(&blocked))
		require.True(collect, blocked)
	}, 5*time.Second, 10*time.Millisecond)
}

func readMembershipTime(t *testing.T, db *sql.DB, fileID int64) int64 {
	t.Helper()
	var updationTime int64
	require.NoError(t, db.QueryRow(`SELECT updation_time FROM collection_files WHERE file_id = $1`, fileID).Scan(&updationTime))
	return updationTime
}

func setupMagicMetadataTest(t *testing.T, stored ente.MagicMetadata, isPublic bool) (*sql.DB, *FileRepository, int64, int64) {
	t.Helper()
	db := setupFileUsageTest(t)
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "owner@example.com", CreationTime: 1})
	fileID := insertObjectTestFile(t, db, ownerID)
	linkObjectTestFileToCollection(t, db, insertObjectTestCollection(t, db, ownerID), fileID, ownerID)
	_, err := db.Exec(`UPDATE files SET `+magicMetadataColumn(isPublic)+` = $1 WHERE file_id = $2`, stored, fileID)
	require.NoError(t, err)
	return db, &FileRepository{DB: db}, ownerID, fileID
}

func readMagicMetadata(t *testing.T, db *sql.DB, fileID int64, isPublic bool) ente.MagicMetadata {
	t.Helper()
	var metadata ente.MagicMetadata
	require.NoError(t, db.QueryRow(`SELECT `+magicMetadataColumn(isPublic)+` FROM files WHERE file_id = $1`, fileID).Scan(&metadata))
	return metadata
}

func magicMetadataColumn(isPublic bool) string {
	if isPublic {
		return "pub_magic_metadata"
	}
	return "magic_metadata"
}
