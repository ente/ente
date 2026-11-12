package repo

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/stretchr/testify/require"
)

func TestObjectCopiesReplicationQueue(t *testing.T) {
	for _, tc := range []struct {
		name        string
		b2          *int64
		wasabi      *int64
		scw         *int64
		wantB2      bool
		lastAttempt int64
		selected    bool
	}{
		{name: "missing only b2", wasabi: replicationTimestamp(), scw: replicationTimestamp(), wantB2: true, selected: true},
		{name: "missing wasabi", b2: replicationTimestamp(), scw: replicationTimestamp(), wantB2: true, selected: true},
		{name: "missing scaleway", b2: replicationTimestamp(), wasabi: replicationTimestamp(), wantB2: true, selected: true},
		{name: "missing wasabi and scaleway", b2: replicationTimestamp(), wantB2: true, selected: true},
		{name: "complete", b2: replicationTimestamp(), wasabi: replicationTimestamp(), scw: replicationTimestamp(), wantB2: true},
		{name: "unwanted b2", wasabi: replicationTimestamp(), scw: replicationTimestamp()},
		{name: "recent b2 attempt", wasabi: replicationTimestamp(), scw: replicationTimestamp(), wantB2: true, lastAttempt: time.Now().UnixMicro()},
		{name: "recent wasabi attempt", b2: replicationTimestamp(), scw: replicationTimestamp(), wantB2: true, lastAttempt: time.Now().UnixMicro()},
		{name: "recent scaleway attempt", b2: replicationTimestamp(), wasabi: replicationTimestamp(), wantB2: true, lastAttempt: time.Now().UnixMicro()},
	} {
		t.Run(tc.name, func(t *testing.T) {
			db := setupFileUsageTest(t)
			ownerID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "replication-queue@example.com", CreationTime: 1})
			fileID := insertObjectTestFile(t, db, ownerID)
			insertObjectTestKey(t, db, fileID, ente.FILE, "replication-queue", 100, []string{"wasabi-eu-central-2-v3"})
			_, err := db.Exec(`INSERT INTO object_copies (object_key, b2, wasabi, scw, want_b2, want_wasabi, want_scw, last_attempt)
				VALUES ('replication-queue', $1, $2, $3, $4, true, true, $5)`, tc.b2, tc.wasabi, tc.scw, tc.wantB2, tc.lastAttempt)
			require.NoError(t, err)
			repository := &ObjectCopiesRepository{DB: db}
			copies, err := repository.GetAndLockUnreplicatedObject(t.Context())
			if !tc.selected {
				require.ErrorIs(t, err, sql.ErrNoRows)
				return
			}
			require.NoError(t, err)
			require.Equal(t, &ente.ObjectCopies{ObjectKey: "replication-queue", B2: tc.b2, Wasabi: tc.wasabi, SCW: tc.scw,
				WantB2: tc.wantB2, WantWasabi: true, WantSCW: true}, copies)
			for range 3 {
				_, err = repository.GetAndLockUnreplicatedObject(t.Context())
				require.ErrorIs(t, err, sql.ErrNoRows)
			}
		})
	}
}

func TestObjectCopiesReplicationDestinationRotation(t *testing.T) {
	db := setupFileUsageTest(t)
	insertReplicationQueueObjects(t, db)
	repository := &ObjectCopiesRepository{DB: db}

	for range 2 {
		for _, key := range []string{"b2", "wasabi", "scw"} {
			copies, err := repository.GetAndLockUnreplicatedObject(t.Context())
			require.NoError(t, err)
			require.Equal(t, key, copies.ObjectKey)
			_, err = db.Exec(`UPDATE object_copies SET last_attempt = 0`)
			require.NoError(t, err)
		}
	}
}

func TestObjectCopiesReplicationSkipsLockedObjects(t *testing.T) {
	db := setupFileUsageTest(t)
	insertReplicationQueueObjects(t, db)
	tx, err := db.BeginTx(t.Context(), nil)
	require.NoError(t, err)
	defer tx.Rollback()
	_, err = tx.ExecContext(t.Context(), `SELECT object_key FROM object_copies WHERE object_key = 'b2' FOR UPDATE`)
	require.NoError(t, err)

	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	repository := &ObjectCopiesRepository{DB: db}
	for _, key := range []string{"wasabi", "scw"} {
		copies, err := repository.GetAndLockUnreplicatedObject(ctx)
		require.NoError(t, err)
		require.Equal(t, key, copies.ObjectKey)
	}
	_, err = repository.GetAndLockUnreplicatedObject(ctx)
	require.ErrorIs(t, err, sql.ErrNoRows)
	require.NoError(t, tx.Rollback())
	copies, err := repository.GetAndLockUnreplicatedObject(ctx)
	require.NoError(t, err)
	require.Equal(t, "b2", copies.ObjectKey)
}

func TestObjectCopiesReplicationConcurrentClaims(t *testing.T) {
	db := setupFileUsageTest(t)
	insertReplicationQueueObjects(t, db)
	_, err := db.Exec(`UPDATE object_copies SET b2 = 1, wasabi = NULL, scw = NULL`)
	require.NoError(t, err)

	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	defer cancel()
	repositories := []*ObjectCopiesRepository{{DB: db}, {DB: db}}
	type result struct {
		copies *ente.ObjectCopies
		err    error
	}
	const workers = 12
	results := make(chan result, workers)
	start := make(chan struct{})
	for i := range workers {
		go func() {
			<-start
			copies, err := repositories[i%len(repositories)].GetAndLockUnreplicatedObject(ctx)
			results <- result{copies: copies, err: err}
		}()
	}
	close(start)
	var completed []result
	for range workers {
		completed = append(completed, <-results)
	}
	var keys []string
	for _, result := range completed {
		if result.err != nil {
			require.ErrorIs(t, result.err, sql.ErrNoRows)
			continue
		}
		require.True(t, result.copies.WantWasabi && result.copies.WantSCW)
		require.Nil(t, result.copies.Wasabi)
		require.Nil(t, result.copies.SCW)
		keys = append(keys, result.copies.ObjectKey)
	}
	require.ElementsMatch(t, []string{"b2", "wasabi", "scw"}, keys)
}

func insertReplicationQueueObjects(t *testing.T, db *sql.DB) {
	t.Helper()
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "replication-queue@example.com", CreationTime: 1})
	for _, destination := range []string{"b2", "wasabi", "scw"} {
		fileID := insertObjectTestFile(t, db, ownerID)
		insertObjectTestKey(t, db, fileID, ente.FILE, destination, 100, []string{"wasabi-eu-central-2-v3"})
		_, err := db.Exec(`INSERT INTO object_copies (object_key, b2, wasabi, scw, want_b2, want_wasabi, want_scw)
			VALUES ($1, CASE WHEN $1 = 'b2' THEN NULL ELSE 1 END,
				CASE WHEN $1 = 'wasabi' THEN NULL ELSE 1 END,
				CASE WHEN $1 = 'scw' THEN NULL ELSE 1 END, true, true, true)`, destination)
		require.NoError(t, err)
	}
}

func replicationTimestamp() *int64 {
	timestamp := int64(1)
	return &timestamp
}
