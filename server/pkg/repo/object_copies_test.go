package repo

import (
	"context"
	"database/sql"
	"slices"
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

func TestObjectCopiesResetReplication(t *testing.T) {
	for _, tc := range []struct {
		name         string
		sourceIsB2   bool
		wantScaleway bool
	}{
		{name: "b2 file", sourceIsB2: true, wantScaleway: true},
		{name: "wasabi file", wantScaleway: true},
		{name: "b2 thumbnail", sourceIsB2: true},
		{name: "wasabi thumbnail"},
	} {
		for _, state := range []string{"retained", "pruned"} {
			t.Run(tc.name+"/"+state, func(t *testing.T) {
				db := setupFileUsageTest(t)
				ownerID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "replication-reset@example.com", CreationTime: 1})
				fileID := insertObjectTestFile(t, db, ownerID)
				objectType := ente.THUMBNAIL
				locations := []string{"wasabi-eu-central-2-v3", "b2-eu-cen"}
				if tc.sourceIsB2 {
					locations[0], locations[1] = locations[1], locations[0]
				}
				if tc.wantScaleway {
					objectType = ente.FILE
					locations = append(locations, "scw-eu-fr-v3")
				}
				const objectKey = "replication-reset"
				insertObjectTestKey(t, db, fileID, objectType, objectKey, 100, locations)
				_, err := db.Exec(`INSERT INTO object_copies (object_key, b2, wasabi, scw, want_b2, want_wasabi, want_scw, last_attempt)
					VALUES ($1, 1, 1, CASE WHEN $2 THEN 1 END, true, true, $2, now_utc_micro_seconds())`, objectKey, tc.wantScaleway)
				require.NoError(t, err)
				if state == "pruned" {
					_, err = db.Exec(`DELETE FROM object_copies WHERE object_key = $1`, objectKey)
					require.NoError(t, err)
				}

				repository := &ObjectCopiesRepository{DB: db}
				require.NoError(t, repository.ResetReplication(objectKey, tc.sourceIsB2, tc.wantScaleway))
				copies, err := repository.GetAndLockUnreplicatedObject(t.Context())
				require.NoError(t, err)
				require.Equal(t, objectKey, copies.ObjectKey)
				require.True(t, copies.WantB2)
				require.True(t, copies.WantWasabi)
				require.Equal(t, tc.wantScaleway, copies.WantSCW)
				require.Nil(t, copies.SCW)
				source, destination := copies.Wasabi, copies.B2
				if tc.sourceIsB2 {
					source, destination = copies.B2, copies.Wasabi
				}
				require.NotNil(t, source)
				require.Positive(t, *source)
				require.Nil(t, destination)
			})
		}
	}
}

func TestObjectCopiesPrunesCompletedReplication(t *testing.T) {
	for _, tc := range []struct {
		name         string
		source       string
		destinations []string
	}{
		{name: "b2 original", source: "b2", destinations: []string{"wasabi", "scw"}},
		{name: "wasabi original", source: "wasabi", destinations: []string{"b2", "scw"}},
		{name: "wasabi completes last", source: "b2", destinations: []string{"scw", "wasabi"}},
		{name: "b2 completes last", source: "wasabi", destinations: []string{"scw", "b2"}},
		{name: "b2 thumbnail", source: "b2", destinations: []string{"wasabi"}},
		{name: "wasabi thumbnail", source: "wasabi", destinations: []string{"b2"}},
		{name: "wasabi not required", source: "b2", destinations: []string{"scw"}},
		{name: "b2 not required", source: "wasabi", destinations: []string{"scw"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			db := setupFileUsageTest(t)
			ownerID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "replication-prune@example.com", CreationTime: 1})
			fileID := insertObjectTestFile(t, db, ownerID)
			const objectKey = "replication-prune"
			objectType := ente.FILE
			if !slices.Contains(tc.destinations, "scw") {
				objectType = ente.THUMBNAIL
			}
			source := "b2-eu-cen"
			if tc.source == "wasabi" {
				source = "wasabi-eu-central-2-v3"
			}
			insertObjectTestKey(t, db, fileID, objectType, objectKey, 100, []string{source})
			otherFileID := insertObjectTestFile(t, db, ownerID)
			insertObjectTestKey(t, db, otherFileID, ente.FILE, "other-completed-object", 100,
				[]string{"b2-eu-cen", "wasabi-eu-central-2-v3", "scw-eu-fr-v3"})
			_, err := db.Exec(`INSERT INTO object_copies (object_key, b2, wasabi, scw, want_b2, want_wasabi, want_scw)
				VALUES ('other-completed-object', 1, 1, 1, true, true, true)`)
			require.NoError(t, err)
			repository := &ObjectCopiesRepository{DB: db}
			tx, err := db.BeginTx(t.Context(), nil)
			require.NoError(t, err)
			defer tx.Rollback()
			if tc.source == "b2" {
				err = repository.CreateNewB2Object(t.Context(), tx, objectKey,
					slices.Contains(tc.destinations, "wasabi"), slices.Contains(tc.destinations, "scw"))
			} else {
				err = repository.CreateNewWasabiObject(t.Context(), tx, objectKey,
					slices.Contains(tc.destinations, "b2"), slices.Contains(tc.destinations, "scw"))
			}
			require.NoError(t, err)
			require.NoError(t, tx.Commit())

			markReplicated := map[string]func(string) error{
				"b2": repository.MarkObjectReplicatedB2, "wasabi": repository.MarkObjectReplicatedWasabi,
				"scw": repository.MarkObjectReplicatedScaleway,
			}
			for i, destination := range tc.destinations {
				var exists bool
				require.NoError(t, db.QueryRow(`SELECT EXISTS (SELECT 1 FROM object_copies WHERE object_key = $1)`, objectKey).Scan(&exists))
				require.True(t, exists, "retain the job until every required destination is recorded")
				require.NoError(t, markReplicated[destination](objectKey))
				require.NoError(t, db.QueryRow(`SELECT EXISTS (SELECT 1 FROM object_copies WHERE object_key = $1)`, objectKey).Scan(&exists))
				require.Equal(t, i < len(tc.destinations)-1, exists)
			}
			var keys, copies int
			require.NoError(t, db.QueryRow(`SELECT count(*) FROM object_keys WHERE object_key IN ($1, 'other-completed-object')`, objectKey).Scan(&keys))
			require.Equal(t, 2, keys)
			require.NoError(t, db.QueryRow(`SELECT count(*) FROM object_copies WHERE object_key = 'other-completed-object'`).Scan(&copies))
			require.Equal(t, 1, copies)
		})
	}
}

func TestObjectCopiesPruningFailureRollsBackCompletion(t *testing.T) {
	db := setupFileUsageTest(t)
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{Email: "replication-prune-failure@example.com", CreationTime: 1})
	fileID := insertObjectTestFile(t, db, ownerID)
	const objectKey = "replication-prune-failure"
	insertObjectTestKey(t, db, fileID, ente.FILE, objectKey, 100, []string{"wasabi-eu-central-2-v3", "scw-eu-fr-v3"})
	_, err := db.Exec(`INSERT INTO object_copies (object_key, wasabi, scw, want_b2, want_wasabi, want_scw)
		VALUES ($1, 1, 1, true, true, true)`, objectKey)
	require.NoError(t, err)
	_, err = db.Exec(`CREATE FUNCTION fail_replication_pruning() RETURNS trigger LANGUAGE plpgsql AS $$
		BEGIN RAISE EXCEPTION 'replication pruning failed'; END;
		$$;
		CREATE TRIGGER fail_replication_pruning BEFORE DELETE ON object_copies
		FOR EACH ROW EXECUTE FUNCTION fail_replication_pruning()`)
	require.NoError(t, err)
	t.Cleanup(func() {
		_, err := db.Exec(`DROP TRIGGER IF EXISTS fail_replication_pruning ON object_copies; DROP FUNCTION fail_replication_pruning()`)
		require.NoError(t, err)
	})
	repository := &ObjectCopiesRepository{DB: db}
	require.ErrorContains(t, repository.MarkObjectReplicatedB2(objectKey), "replication pruning failed")
	copies, err := repository.GetAndLockUnreplicatedObject(t.Context())
	require.NoError(t, err)
	require.Equal(t, objectKey, copies.ObjectKey)
	require.Nil(t, copies.B2)
	require.Equal(t, replicationTimestamp(), copies.Wasabi)
	require.Equal(t, replicationTimestamp(), copies.SCW)

	_, err = db.Exec(`DROP TRIGGER fail_replication_pruning ON object_copies`)
	require.NoError(t, err)
	require.NoError(t, repository.MarkObjectReplicatedB2(objectKey))
	var count int
	require.NoError(t, db.QueryRow(`SELECT count(*) FROM object_copies WHERE object_key = $1`, objectKey).Scan(&count))
	require.Zero(t, count)
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
