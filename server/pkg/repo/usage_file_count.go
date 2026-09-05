package repo

import (
	"context"
	"database/sql"
	"errors"

	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
	"github.com/lib/pq"
	"github.com/sirupsen/logrus"
)

func applyUsageDelta(
	ctx context.Context,
	tx *sql.Tx,
	userID int64,
	storageDelta int64,
	photosFileDelta int64,
	lockerFileDelta int64,
	invalidateFileCounts bool,
) (int64, error) {
	row := tx.QueryRowContext(ctx, `WITH current_usage AS (
			SELECT user_id, storage_consumed, photos_file_count, locker_file_count, file_count_source_version
			FROM usage
			WHERE user_id = $1
			FOR UPDATE
		)
		UPDATE usage AS target
		SET storage_consumed = current_usage.storage_consumed + $2,
			photos_file_count = CASE
				WHEN $5
					OR current_usage.photos_file_count IS NULL
					OR current_usage.locker_file_count IS NULL
					OR current_usage.photos_file_count + $3 < 0
					OR current_usage.locker_file_count + $4 < 0
				THEN NULL
				ELSE current_usage.photos_file_count + $3
			END,
			locker_file_count = CASE
				WHEN $5
					OR current_usage.photos_file_count IS NULL
					OR current_usage.locker_file_count IS NULL
					OR current_usage.photos_file_count + $3 < 0
					OR current_usage.locker_file_count + $4 < 0
				THEN NULL
				ELSE current_usage.locker_file_count + $4
			END,
			file_count_source_version = current_usage.file_count_source_version
				+ CASE WHEN $3 <> 0 OR $4 <> 0 OR $5 THEN 1 ELSE 0 END
		FROM current_usage
		WHERE target.user_id = current_usage.user_id
		RETURNING target.storage_consumed,
			current_usage.photos_file_count IS NOT NULL
			AND current_usage.locker_file_count IS NOT NULL
			AND ($5 OR current_usage.photos_file_count + $3 < 0 OR current_usage.locker_file_count + $4 < 0)`,
		userID,
		storageDelta,
		photosFileDelta,
		lockerFileDelta,
		invalidateFileCounts,
	)
	var storageConsumed int64
	var fileCountsInvalidated bool
	if err := row.Scan(&storageConsumed, &fileCountsInvalidated); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return -1, stacktrace.NewError("missing usage row for user %d", userID)
		}
		return -1, stacktrace.Propagate(err, "")
	}
	if fileCountsInvalidated {
		logrus.WithFields(logrus.Fields{
			"user_id":           userID,
			"photos_file_delta": photosFileDelta,
			"locker_file_delta": lockerFileDelta,
		}).Error("invalidated file counts")
	}
	return storageConsumed, nil
}

func fileCountDelta(app ente.App, delta int64) (photos int64, locker int64, ok bool) {
	switch app {
	case ente.Photos:
		return delta, 0, true
	case ente.Locker:
		return 0, delta, true
	default:
		return 0, 0, false
	}
}

func activeOwnedFileCountDeltas(ctx context.Context, tx *sql.Tx, userID int64, fileIDs []int64) (photos int64, locker int64, ambiguous bool, err error) {
	err = tx.QueryRowContext(ctx, `WITH active_apps AS (
			SELECT DISTINCT cf.file_id, c.app
			FROM collection_files AS cf
			JOIN files AS f ON f.file_id = cf.file_id AND f.owner_id = $1
			JOIN collections AS c ON c.collection_id = cf.collection_id AND c.owner_id = $1
			WHERE cf.file_id = ANY($2) AND cf.is_deleted = FALSE
		)
		SELECT
			-COUNT(*) FILTER (WHERE app = $3),
			-COUNT(*) FILTER (WHERE app = $4),
			COUNT(*) <> COUNT(DISTINCT file_id)
				OR COUNT(*) FILTER (WHERE app IS NULL OR app NOT IN ($3, $4)) > 0
		FROM active_apps`, userID, pq.Array(fileIDs), ente.Photos, ente.Locker).Scan(&photos, &locker, &ambiguous)
	if err != nil {
		return 0, 0, false, stacktrace.Propagate(err, "")
	}
	return photos, locker, ambiguous, nil
}

func inactiveOwnedFileCount(ctx context.Context, tx *sql.Tx, userID int64, fileIDs []int64) (int64, error) {
	row := tx.QueryRowContext(ctx, `SELECT COUNT(*)
		FROM files AS f
		WHERE f.owner_id = $1 AND f.file_id = ANY($2)
			AND NOT EXISTS (
			SELECT 1
			FROM collection_files AS cf
			JOIN collections AS c ON c.collection_id = cf.collection_id AND c.owner_id = $1
			WHERE cf.file_id = f.file_id AND cf.is_deleted = FALSE
		)`, userID, pq.Array(fileIDs))
	var count int64
	if err := row.Scan(&count); err != nil {
		return 0, stacktrace.Propagate(err, "")
	}
	return count, nil
}
