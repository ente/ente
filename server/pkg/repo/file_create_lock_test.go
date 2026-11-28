package repo

import (
	"context"
	"database/sql"
	"fmt"
	"math"
	"sync"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/lib/pq"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

var testCreateBuckets = FileObjectBuckets{File: "b2-eu-cen", Thumbnail: "b2-eu-cen"}

func TestFileCreateTakesCollectionAndUsageLocksAfterObjectWork(t *testing.T) {
	t.Run("commit", func(t *testing.T) {
		repo, file := setupFileCreateLockTest(t)
		ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
		defer cancel()

		objects, err := repo.DB.BeginTx(ctx, nil)
		require.NoError(t, err)
		defer objects.Rollback()
		var objectPID int
		require.NoError(t, objects.QueryRowContext(ctx, `SELECT pg_backend_pid()`).Scan(&objectPID))
		_, err = objects.ExecContext(ctx, `SELECT 1 FROM temp_objects WHERE object_key = $1 FOR UPDATE`, file.Thumbnail.ObjectKey)
		require.NoError(t, err)

		type result struct {
			file ente.File
			err  error
		}
		completed := make(chan result, 1)
		go func() {
			created, _, err := repo.Create(file, 200, 20, 220, file.OwnerID, ente.Photos, testCreateBuckets)
			completed <- result{created, err}
		}()
		finished := false
		t.Cleanup(func() {
			_ = objects.Rollback()
			if !finished {
				select {
				case <-completed:
				case <-time.After(5 * time.Second):
					t.Error("file create did not finish after releasing blockers")
				}
			}
		})

		waitForCreateBlocker(t, ctx, repo.DB, objectPID)

		// Object bookkeeping must not hold the collection write lock. FOR NO KEY
		// UPDATE is compatible with collection_files's foreign-key KEY SHARE lock.
		probe, err := repo.DB.BeginTx(ctx, nil)
		require.NoError(t, err)
		defer probe.Rollback()
		_, err = probe.ExecContext(ctx, `SELECT 1 FROM collections WHERE collection_id = $1 FOR NO KEY UPDATE NOWAIT`, file.CollectionID)
		require.NoError(t, err)
		require.NoError(t, probe.Rollback())

		usage, err := repo.DB.BeginTx(ctx, nil)
		require.NoError(t, err)
		defer usage.Rollback()
		var usagePID int
		require.NoError(t, usage.QueryRowContext(ctx, `SELECT pg_backend_pid()`).Scan(&usagePID))
		_, err = usage.ExecContext(ctx, `SELECT 1 FROM usage WHERE user_id = $1 FOR UPDATE NOWAIT`, file.OwnerID)
		require.NoError(t, err)

		require.NoError(t, objects.Commit())
		waitForCreateBlocker(t, ctx, repo.DB, usagePID)

		// Collections must be locked before usage.
		probe, err = repo.DB.BeginTx(ctx, nil)
		require.NoError(t, err)
		defer probe.Rollback()
		_, err = probe.ExecContext(ctx, `SELECT 1 FROM collections WHERE collection_id = $1 FOR NO KEY UPDATE NOWAIT`, file.CollectionID)
		var pgErr *pq.Error
		require.ErrorAs(t, err, &pgErr)
		require.Equal(t, pq.ErrorCode("55P03"), pgErr.Code)
		require.NoError(t, probe.Rollback())

		require.NoError(t, usage.Commit())
		written := <-completed
		finished = true
		require.NoError(t, written.err)
		require.Greater(t, written.file.UpdationTime, int64(1))
		assertFileCreateVersionsMatch(t, repo.DB, file.CollectionID, written.file.ID, written.file.UpdationTime)

		var storage int64
		var photos int
		require.NoError(t, repo.DB.QueryRow(`SELECT storage_consumed, photos_file_count FROM usage WHERE user_id = $1`, file.OwnerID).Scan(&storage, &photos))
		require.Equal(t, int64(330), storage)
		require.Equal(t, 2, photos)
		assertCreateLockTestRowCounts(t, repo.DB, 2, 0)
	})

	t.Run("rollback", func(t *testing.T) {
		repo, file := setupFileCreateLockTest(t)
		_, err := repo.DB.Exec(`DELETE FROM usage WHERE user_id = $1`, file.OwnerID)
		require.NoError(t, err)

		_, _, err = repo.Create(file, 200, 20, 220, file.OwnerID, ente.Photos, testCreateBuckets)
		require.ErrorContains(t, err, "missing usage row")
		assertCreateRollbackState(t, repo.DB, file.CollectionID)
	})
}

func TestCreateRemainsVisibleAfterNewerCommit(t *testing.T) {
	for _, concurrentWrite := range []string{"upload", "rename"} {
		t.Run(concurrentWrite, func(t *testing.T) {
			repository, file := setupFileCreateLockTest(t)
			collections := &CollectionRepository{
				DB: repository.DB,
				LatencyLogger: prometheus.NewHistogramVec(
					prometheus.HistogramOpts{Name: "collection_create_sync_test"}, []string{"method"},
				),
			}
			ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
			defer cancel()

			blocker, err := repository.DB.BeginTx(ctx, nil)
			require.NoError(t, err)
			defer blocker.Rollback()
			var pid int
			require.NoError(t, blocker.QueryRowContext(ctx, `SELECT pg_backend_pid()`).Scan(&pid))
			_, err = blocker.ExecContext(ctx, `SELECT 1 FROM temp_objects WHERE object_key = $1 FOR UPDATE`, file.Thumbnail.ObjectKey)
			require.NoError(t, err)

			type result struct {
				file ente.File
				err  error
			}
			completed := make(chan result, 1)
			go func() {
				created, _, err := repository.Create(file, 200, 20, 220, file.OwnerID, ente.Photos, testCreateBuckets)
				completed <- result{created, err}
			}()
			finished := false
			t.Cleanup(func() {
				_ = blocker.Rollback()
				if !finished {
					select {
					case <-completed:
					case <-time.After(5 * time.Second):
						t.Error("upload did not finish after releasing blocker")
					}
				}
			})

			waitForCreateBlocker(t, ctx, repository.DB, pid)
			if concurrentWrite == "rename" {
				require.NoError(t, collections.Rename(file.CollectionID, "renamed", "nonce"))
			} else {
				newer := newTestUploadFile(file.OwnerID, file.CollectionID, "concurrent-file", "concurrent-thumbnail", time.Now().UnixMicro())
				stageCreateTestObjects(t, repository.DB, newer.File.ObjectKey, newer.Thumbnail.ObjectKey)
				_, _, err := repository.Create(newer, 200, 20, 220, file.OwnerID, ente.Photos, testCreateBuckets)
				require.NoError(t, err)
			}

			var cursor int64
			require.NoError(t, repository.DB.QueryRowContext(ctx, `SELECT updation_time FROM collections WHERE collection_id = $1`, file.CollectionID).Scan(&cursor))
			// Clients advance to this album version even when its file diff is empty.
			_, err = collections.GetDiff(file.CollectionID, 1, 100, false)
			require.NoError(t, err)

			require.NoError(t, blocker.Commit())
			written := <-completed
			finished = true
			require.NoError(t, written.err)
			require.Greater(t, written.file.UpdationTime, cursor)
			assertFileCreateVersionsMatch(t, repository.DB, file.CollectionID, written.file.ID, written.file.UpdationTime)

			diff, err := collections.GetDiff(file.CollectionID, cursor, 100, false)
			require.NoError(t, err)
			require.Len(t, diff, 1)
			require.Equal(t, written.file.ID, diff[0].ID)
			require.Equal(t, written.file.UpdationTime, diff[0].UpdationTime)
		})
	}
}

func TestCreateAdvancesPastFutureCollectionVersion(t *testing.T) {
	repository, file := setupFileCreateLockTest(t)
	previous := time.Now().Add(time.Hour).UnixMicro()
	_, err := repository.DB.Exec(`UPDATE collections SET updation_time = $1 WHERE collection_id = $2`, previous, file.CollectionID)
	require.NoError(t, err)

	created, _, err := repository.Create(file, 200, 20, 220, file.OwnerID, ente.Photos, testCreateBuckets)
	require.NoError(t, err)
	require.Equal(t, previous+1, created.UpdationTime)
	assertFileCreateVersionsMatch(t, repository.DB, file.CollectionID, created.ID, previous+1)
}

func TestCreateIgnoresCallerUpdationTime(t *testing.T) {
	repository, file := setupFileCreateLockTest(t)
	db := repository.DB
	file.UpdationTime = math.MaxInt64

	before := time.Now().UnixMicro()
	created, _, err := repository.Create(file, 200, 20, 220, file.OwnerID, ente.Photos, testCreateBuckets)
	after := time.Now().UnixMicro()
	require.NoError(t, err)
	require.GreaterOrEqual(t, created.UpdationTime, before)
	require.LessOrEqual(t, created.UpdationTime, after)
	assertFileCreateVersionsMatch(t, db, file.CollectionID, created.ID, created.UpdationTime)

	stageCreateTestObjects(t, db, "after-max-file", "after-max-thumb")
	next := newTestUploadFile(file.OwnerID, file.CollectionID, "after-max-file", "after-max-thumb", 1)

	pool, err := sql.Open("postgres", "sslmode=disable")
	require.NoError(t, err)
	t.Cleanup(func() { _ = pool.Close() })
	pool.SetMaxOpenConns(1)
	repository.DB = pool

	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	defer cancel()
	holder, err := pool.BeginTx(ctx, nil)
	require.NoError(t, err)
	defer holder.Rollback()
	var one int
	require.NoError(t, holder.QueryRowContext(ctx, `SELECT 1`).Scan(&one))

	beforeCall := time.Now().UnixMicro()
	type result struct {
		file ente.File
		err  error
	}
	completed := make(chan result, 1)
	go func() {
		second, _, err := repository.Create(next, 200, 20, 220, file.OwnerID, ente.Photos, testCreateBuckets)
		completed <- result{second, err}
	}()
	finished := false
	t.Cleanup(func() {
		_ = holder.Rollback()
		if !finished {
			<-completed
		}
	})

	require.Eventually(t, func() bool {
		return pool.Stats().WaitCount == 1
	}, 5*time.Second, time.Millisecond)
	for time.Now().UnixMicro() <= max(beforeCall, created.UpdationTime+1) {
	}
	releasedAt := time.Now().UnixMicro()
	require.NoError(t, holder.Rollback())

	written := <-completed
	afterSecond := time.Now().UnixMicro()
	finished = true
	require.NoError(t, written.err)
	require.GreaterOrEqual(t, written.file.UpdationTime, releasedAt)
	require.LessOrEqual(t, written.file.UpdationTime, afterSecond)
	assertFileCreateVersionsMatch(t, db, file.CollectionID, written.file.ID, written.file.UpdationTime)
}

func TestCreateConcurrentUploadsStrictlyIncreaseVersion(t *testing.T) {
	repository, base := setupFileCreateLockTest(t)
	const workers = 8
	uploads := make([]ente.File, workers)
	for i := range workers {
		fileKey := fmt.Sprintf("concurrent-file-%d", i)
		thumbKey := fmt.Sprintf("concurrent-thumb-%d", i)
		stageCreateTestObjects(t, repository.DB, fileKey, thumbKey)
		uploads[i] = newTestUploadFile(base.OwnerID, base.CollectionID, fileKey, thumbKey, 2)
	}

	type result struct {
		file ente.File
		err  error
	}
	results := make([]result, workers)
	start := make(chan struct{})
	var ready sync.WaitGroup
	var wg sync.WaitGroup
	ready.Add(workers)
	wg.Add(workers)
	for i := range workers {
		go func(idx int) {
			defer wg.Done()
			ready.Done()
			<-start
			created, _, err := repository.Create(uploads[idx], 200, 20, 220, base.OwnerID, ente.Photos, testCreateBuckets)
			results[idx] = result{created, err}
		}(i)
	}
	ready.Wait()
	close(start)
	wg.Wait()

	seenTimes := make(map[int64]struct{}, workers)
	var maxTime int64
	for _, res := range results {
		require.NoError(t, res.err)
		_, dup := seenTimes[res.file.UpdationTime]
		require.False(t, dup, "duplicate updation_time %d across concurrent creates", res.file.UpdationTime)
		seenTimes[res.file.UpdationTime] = struct{}{}
		maxTime = max(maxTime, res.file.UpdationTime)

		var fileTime, membershipTime int64
		require.NoError(t, repository.DB.QueryRow(`SELECT f.updation_time, cf.updation_time
			FROM files f JOIN collection_files cf USING (file_id)
			WHERE cf.collection_id = $1 AND f.file_id = $2`, base.CollectionID, res.file.ID).
			Scan(&fileTime, &membershipTime))
		require.Equal(t, res.file.UpdationTime, fileTime)
		require.Equal(t, res.file.UpdationTime, membershipTime)
	}

	var collectionTime int64
	require.NoError(t, repository.DB.QueryRow(`SELECT updation_time FROM collections WHERE collection_id = $1`, base.CollectionID).Scan(&collectionTime))
	require.Equal(t, maxTime, collectionTime)
}

func TestCreateDuplicateObjectAndMissingCollectionRollBack(t *testing.T) {
	t.Run("duplicate file object", func(t *testing.T) {
		repo, file := setupFileCreateLockTest(t)
		file.File.ObjectKey = "lock-old-file"
		_, _, err := repo.Create(file, 200, 20, 220, file.OwnerID, ente.Photos, testCreateBuckets)
		require.ErrorIs(t, err, ente.ErrDuplicateFileObjectFound)
		assertCreateRollbackState(t, repo.DB, file.CollectionID)
	})

	t.Run("duplicate thumbnail object", func(t *testing.T) {
		repo, file := setupFileCreateLockTest(t)
		file.Thumbnail.ObjectKey = "lock-old-thumbnail"
		_, _, err := repo.Create(file, 200, 20, 220, file.OwnerID, ente.Photos, testCreateBuckets)
		require.ErrorIs(t, err, ente.ErrDuplicateThumbnailObjectFound)
		assertCreateRollbackState(t, repo.DB, file.CollectionID)
	})

	t.Run("missing collection", func(t *testing.T) {
		repo, file := setupFileCreateLockTest(t)
		existingCollectionID := file.CollectionID
		file.CollectionID = existingCollectionID + 9999
		_, _, err := repo.Create(file, 200, 20, 220, file.OwnerID, ente.Photos, testCreateBuckets)
		require.Error(t, err)
		assertCreateRollbackState(t, repo.DB, existingCollectionID)
	})
}

func TestCreateRollsBackWhenCollectionDeletedDuringObjectWork(t *testing.T) {
	repository, file := setupFileCreateLockTest(t)
	collections := &CollectionRepository{
		DB:        repository.DB,
		QueueRepo: &QueueRepository{DB: repository.DB},
	}
	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	defer cancel()

	blocker, err := repository.DB.BeginTx(ctx, nil)
	require.NoError(t, err)
	defer blocker.Rollback()
	var pid int
	require.NoError(t, blocker.QueryRowContext(ctx, `SELECT pg_backend_pid()`).Scan(&pid))
	_, err = blocker.ExecContext(ctx, `SELECT 1 FROM temp_objects WHERE object_key = $1 FOR UPDATE`, file.Thumbnail.ObjectKey)
	require.NoError(t, err)

	type result struct {
		file ente.File
		err  error
	}
	completed := make(chan result, 1)
	go func() {
		created, _, err := repository.Create(file, 200, 20, 220, file.OwnerID, ente.Photos, testCreateBuckets)
		completed <- result{created, err}
	}()
	finished := false
	t.Cleanup(func() {
		_ = blocker.Rollback()
		if !finished {
			select {
			case <-completed:
			case <-time.After(5 * time.Second):
				t.Error("file create did not finish after releasing blocker")
			}
		}
	})

	waitForCreateBlocker(t, ctx, repository.DB, pid)
	require.NoError(t, collections.ScheduleDelete(file.CollectionID))

	require.NoError(t, blocker.Commit())
	written := <-completed
	finished = true
	require.ErrorIs(t, written.err, ente.ErrCollectionDeleted)

	assertCreateLockTestRowCounts(t, repository.DB, 1, 2)
	var newKeys int
	require.NoError(t, repository.DB.QueryRow(`SELECT COUNT(*) FROM object_keys WHERE object_key IN ('lock-new-file', 'lock-new-thumbnail')`).Scan(&newKeys))
	require.Zero(t, newKeys)

	var storage int64
	var photos int
	require.NoError(t, repository.DB.QueryRow(`SELECT storage_consumed, photos_file_count FROM usage WHERE user_id = $1`, file.OwnerID).Scan(&storage, &photos))
	require.Equal(t, int64(110), storage)
	require.Equal(t, 1, photos)
}

func setupFileCreateLockTest(t *testing.T) (*FileRepository, ente.File) {
	t.Helper()
	viper.Reset()
	viper.Set("s3.hot_storage.primary", "b2-eu-cen")
	t.Cleanup(viper.Reset)

	db := setupFileUsageTest(t)
	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "file-lock@example.com", CreationTime: 1})
	_, err := db.Exec(`INSERT INTO usage (user_id, storage_consumed, photos_file_count, locker_file_count) VALUES ($1, 110, 1, 0)`, ownerID)
	require.NoError(t, err)

	collectionID := insertObjectTestCollection(t, db, ownerID)
	fileID := insertObjectTestFile(t, db, ownerID)
	linkObjectTestFileToCollection(t, db, collectionID, fileID, ownerID)
	insertObjectTestKey(t, db, fileID, ente.FILE, "lock-old-file", 100, []string{"b2-eu-cen"})
	insertObjectTestKey(t, db, fileID, ente.THUMBNAIL, "lock-old-thumbnail", 10, []string{"b2-eu-cen"})
	_, err = db.Exec(`INSERT INTO object_copies (object_key, b2, want_b2, want_wasabi, want_scw)
		SELECT object_key, 1, TRUE, TRUE, o_type = 'file' FROM object_keys WHERE file_id = $1`, fileID)
	require.NoError(t, err)

	stageCreateTestObjects(t, db, "lock-new-file", "lock-new-thumbnail")
	return &FileRepository{
		DB:                db,
		S3Config:          s3config.NewS3Config(),
		QueueRepo:         &QueueRepository{DB: db},
		ObjectCleanupRepo: &ObjectCleanupRepository{DB: db},
		ObjectCopiesRepo:  &ObjectCopiesRepository{DB: db},
	}, newTestUploadFile(ownerID, collectionID, "lock-new-file", "lock-new-thumbnail", 2)
}

func newTestUploadFile(ownerID, collectionID int64, fileKey, thumbKey string, updationTime int64) ente.File {
	return ente.File{
		OwnerID:            ownerID,
		CollectionID:       collectionID,
		EncryptedKey:       "file-key",
		KeyDecryptionNonce: "file-nonce",
		UpdationTime:       updationTime,
		File:               ente.FileAttributes{ObjectKey: fileKey, DecryptionHeader: "new-file-header"},
		Thumbnail:          ente.FileAttributes{ObjectKey: thumbKey, DecryptionHeader: "new-thumbnail-header"},
		Metadata:           ente.FileAttributes{EncryptedData: "new-metadata", DecryptionHeader: "new-metadata-header"},
		Info:               &ente.FileInfo{FileSize: 200, ThumbnailSize: 20},
	}
}

func stageCreateTestObjects(t *testing.T, db *sql.DB, keys ...string) {
	t.Helper()
	_, err := db.Exec(`INSERT INTO temp_objects (object_key, expiration_time, bucket_id)
		SELECT unnest($1::text[]), 9223372036854775807, 'b2-eu-cen'`, pq.Array(keys))
	require.NoError(t, err)
}

func waitForCreateBlocker(t *testing.T, ctx context.Context, db *sql.DB, pid int) {
	t.Helper()
	for {
		var waiting bool
		require.NoError(t, db.QueryRowContext(ctx, `SELECT EXISTS (
			SELECT 1 FROM pg_stat_activity WHERE datname = current_database()
			AND $1 = ANY(pg_blocking_pids(pid)))`, pid).Scan(&waiting))
		if waiting {
			return
		}
		select {
		case <-ctx.Done():
			t.Fatalf("timed out waiting for blocker pid %d: %v", pid, ctx.Err())
		case <-time.After(10 * time.Millisecond):
		}
	}
}

func assertFileCreateVersionsMatch(t *testing.T, db *sql.DB, collectionID, fileID, want int64) {
	t.Helper()
	var collectionTime, membershipTime, fileTime int64
	require.NoError(t, db.QueryRow(`SELECT c.updation_time, cf.updation_time, f.updation_time
		FROM collections c JOIN collection_files cf USING (collection_id) JOIN files f USING (file_id)
		WHERE c.collection_id = $1 AND f.file_id = $2`, collectionID, fileID).
		Scan(&collectionTime, &membershipTime, &fileTime))
	require.Equal(t, want, collectionTime)
	require.Equal(t, want, membershipTime)
	require.Equal(t, want, fileTime)
}

func assertCreateRollbackState(t *testing.T, db *sql.DB, collectionID int64) {
	t.Helper()
	var collectionTime int64
	require.NoError(t, db.QueryRow(`SELECT updation_time FROM collections WHERE collection_id = $1`, collectionID).Scan(&collectionTime))
	require.Equal(t, int64(1), collectionTime)
	assertCreateLockTestRowCounts(t, db, 1, 2)
	var newKeys int
	require.NoError(t, db.QueryRow(`SELECT COUNT(*) FROM object_keys WHERE object_key IN ('lock-new-file', 'lock-new-thumbnail')`).Scan(&newKeys))
	require.Zero(t, newKeys)
}

func assertCreateLockTestRowCounts(t *testing.T, db *sql.DB, files, staged int) {
	t.Helper()
	for _, tc := range []struct {
		query string
		want  int
	}{
		{`SELECT COUNT(*) FROM files`, files},
		{`SELECT COUNT(*) FROM collection_files`, files},
		{`SELECT COUNT(*) FROM object_keys`, 2 * files},
		{`SELECT COUNT(*) FROM object_copies`, 2 * files},
		{`SELECT COUNT(*) FROM temp_objects`, staged},
	} {
		var count int
		require.NoError(t, db.QueryRow(tc.query).Scan(&count))
		require.Equal(t, tc.want, count, tc.query)
	}
}
