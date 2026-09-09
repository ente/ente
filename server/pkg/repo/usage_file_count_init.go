package repo

import (
	"context"
	"errors"
	"fmt"
)

var ErrFileCountIneligible = errors.New("file counts are ineligible")

func (repo *UsageRepository) InitializeFileCounts(ctx context.Context, userID int64) (bool, error) {
	_, photos, _, err := repo.GetStoredFileCounts(ctx, userID)
	if err != nil || photos != -1 {
		return false, err
	}
	counts, err := repo.readFileCountInitSnapshot(ctx, userID)
	if err != nil {
		return false, err
	}
	if !counts.uninitialized {
		return false, nil
	}
	if counts.ineligibilityReason != "" {
		return false, fmt.Errorf("%w: %s", ErrFileCountIneligible, counts.ineligibilityReason)
	}
	return repo.publishInitialFileCounts(ctx, userID, counts)
}

func (repo *UsageRepository) GetFileCountInitializationCandidates(ctx context.Context, afterUserID int64, limit int) ([]int64, error) {
	rows, err := repo.DB.QueryContext(ctx, `SELECT usage.user_id FROM usage
		JOIN users ON users.user_id = usage.user_id AND users.encrypted_email IS NOT NULL
		WHERE usage.user_id > $1 AND usage.storage_consumed > 0
			AND photos_file_count IS NULL AND locker_file_count IS NULL
		ORDER BY usage.user_id LIMIT $2`, afterUserID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var userIDs []int64
	for rows.Next() {
		var userID int64
		if err := rows.Scan(&userID); err != nil {
			return nil, err
		}
		userIDs = append(userIDs, userID)
	}
	return userIDs, rows.Err()
}

type fileCountInitSnapshot struct {
	photos, locker, version int64
	uninitialized           bool
	ineligibilityReason     string
}

func (repo *UsageRepository) readFileCountInitSnapshot(ctx context.Context, userID int64) (fileCountInitSnapshot, error) {
	var counts fileCountInitSnapshot
	err := repo.DB.QueryRowContext(ctx, `WITH owned_collections AS MATERIALIZED (
		SELECT collection_id, app FROM collections WHERE owner_id = $1
	), memberships AS MATERIALIZED (
		SELECT cf.file_id, c.app, f.owner_id, cf.f_owner_id
		FROM owned_collections AS c
		JOIN collection_files AS cf ON cf.collection_id = c.collection_id AND cf.is_deleted = FALSE
		JOIN files AS f ON f.file_id = cf.file_id
	), owned_files AS MATERIALIZED (
		SELECT DISTINCT file_id FROM memberships WHERE owner_id = $1
	), source AS (
		SELECT
			COUNT(DISTINCT file_id) FILTER (WHERE owner_id = $1 AND app = 'photos') AS photos,
			COUNT(DISTINCT file_id) FILTER (WHERE owner_id = $1 AND app = 'locker') AS locker,
			BOOL_OR(app = 'locker' AND (f_owner_id IS NOT DISTINCT FROM $1) <> (owner_id = $1)) AS locker_mismatch
		FROM memberships
	)
	SELECT u.file_count_source_version,
		u.photos_file_count IS NULL AND u.locker_file_count IS NULL,
		source.photos, source.locker,
		CASE
			WHEN EXISTS (
				SELECT 1
				FROM owned_files AS f
				JOIN collection_files AS cf ON cf.file_id = f.file_id AND cf.is_deleted = FALSE
				JOIN collections AS c ON c.collection_id = cf.collection_id
				GROUP BY f.file_id
				HAVING COUNT(DISTINCT c.app) > 1 OR BOOL_OR(c.app NOT IN ('photos', 'locker'))
			) THEN 'cross-app or unsupported app memberships'
			WHEN EXISTS (
				SELECT 1 FROM owned_files AS f
				JOIN trash AS t ON t.file_id = f.file_id AND t.is_restored = FALSE
			) THEN 'active membership or wrong owner in Trash'
			WHEN source.locker_mismatch THEN 'Locker ownership predicates disagree'
			ELSE ''
		END
	FROM usage AS u CROSS JOIN source
	WHERE u.user_id = $1`, userID).Scan(
		&counts.version, &counts.uninitialized, &counts.photos, &counts.locker, &counts.ineligibilityReason)
	return counts, err
}

func (repo *UsageRepository) publishInitialFileCounts(ctx context.Context, userID int64, counts fileCountInitSnapshot) (bool, error) {
	result, err := repo.DB.ExecContext(ctx, `UPDATE usage
		SET photos_file_count = $2, locker_file_count = $3
		WHERE user_id = $1 AND file_count_source_version = $4
			AND photos_file_count IS NULL AND locker_file_count IS NULL`,
		userID, counts.photos, counts.locker, counts.version)
	if err != nil {
		return false, err
	}
	updated, err := result.RowsAffected()
	return updated == 1, err
}
