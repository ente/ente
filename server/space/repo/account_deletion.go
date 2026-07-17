package repo

import (
	"context"
	"database/sql"

	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

func (m *Module) ResetUserAccess(ctx context.Context, userID int64) error {
	tx, err := m.Spaces.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()

	spaceIDs, err := getOwnedSpaceIDsTx(ctx, tx, userID)
	if err != nil {
		return err
	}
	if err := resetSpaceAccessTx(ctx, tx, userID, spaceIDs); err != nil {
		return err
	}
	return stacktrace.Propagate(tx.Commit(), "")
}

func (m *Module) ResetAccountDeletionAccess(ctx context.Context, userID int64) error {
	tx, err := m.Spaces.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()

	spaceIDs, err := getOwnedSpaceIDsTx(ctx, tx, userID)
	if err != nil {
		return err
	}
	if err := resetAccountDeletionAccessTx(ctx, tx, userID, spaceIDs); err != nil {
		return err
	}
	return stacktrace.Propagate(tx.Commit(), "")
}

func (m *Module) DeleteUserData(ctx context.Context, userID int64) error {
	tx, err := m.Spaces.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()

	spaceIDs, err := getOwnedSpaceIDsTx(ctx, tx, userID)
	if err != nil {
		return err
	}
	if err := queueOwnedSpaceObjectsTx(ctx, tx, userID, spaceIDs); err != nil {
		return err
	}
	if err := deleteSpaceRowsTx(ctx, tx, userID, spaceIDs); err != nil {
		return err
	}
	return stacktrace.Propagate(tx.Commit(), "")
}

func getOwnedSpaceIDsTx(ctx context.Context, tx *sql.Tx, userID int64) ([]string, error) {
	rows, err := tx.QueryContext(ctx, `
		SELECT space_id
		FROM spaces
		WHERE owner_id = $1
		ORDER BY created_at ASC
		FOR UPDATE
	`, userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()

	var spaceIDs []string
	for rows.Next() {
		var spaceID string
		if err := rows.Scan(&spaceID); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		spaceIDs = append(spaceIDs, spaceID)
	}
	return spaceIDs, stacktrace.Propagate(rows.Err(), "")
}

func resetAccountDeletionAccessTx(ctx context.Context, tx *sql.Tx, userID int64, spaceIDs []string) error {
	if _, err := tx.ExecContext(ctx, `DELETE FROM space_browser_sessions WHERE user_id = $1`, userID); err != nil {
		return stacktrace.Propagate(err, "failed to delete space browser sessions")
	}
	return nil
}

func resetSpaceAccessTx(ctx context.Context, tx *sql.Tx, userID int64, spaceIDs []string) error {
	spaceIDArray := pq.Array(spaceIDs)
	if err := resetAccountDeletionAccessTx(ctx, tx, userID, spaceIDs); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM space_friend_shares WHERE space_id = ANY($1) OR friend_space_id = ANY($1)`, spaceIDArray); err != nil {
		return stacktrace.Propagate(err, "failed to delete space friend shares")
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM space_friend_requests WHERE requester_space_id = ANY($1) OR target_space_id = ANY($1)`, spaceIDArray); err != nil {
		return stacktrace.Propagate(err, "failed to delete space friend requests")
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM space_notification_read_markers WHERE viewer_space_id = ANY($1) OR friend_space_id = ANY($1)`, spaceIDArray); err != nil {
		return stacktrace.Propagate(err, "failed to delete space notification read markers")
	}
	return nil
}

func queueOwnedSpaceObjectsTx(ctx context.Context, tx *sql.Tx, userID int64, spaceIDs []string) error {
	if _, err := tx.ExecContext(ctx, `
		UPDATE space_temp_objects
		SET space_id = NULL,
		    expires_at = now_utc_micro_seconds()
		WHERE space_id = ANY($1)
	`, pq.Array(spaceIDs)); err != nil {
		return stacktrace.Propagate(err, "failed to queue staged space uploads for cleanup")
	}

	if err := queueProfileObjectsTx(ctx, tx, userID); err != nil {
		return err
	}
	return queuePostObjectsTx(ctx, tx, spaceIDs)
}

func queueProfileObjectsTx(ctx context.Context, tx *sql.Tx, userID int64) error {
	rows, err := tx.QueryContext(ctx, `
		SELECT a.space_id, a.asset_type, a.object_id, a.bucket_id, COALESCE(NULLIF(a.size, 0), 1)
		FROM space_profile_assets a
		JOIN spaces s ON s.space_id = a.space_id
		WHERE s.owner_id = $1
	`, userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	records := make([]SpaceTempObjectRecord, 0)
	for rows.Next() {
		var rec SpaceTempObjectRecord
		var spaceID, objectID string
		if err := rows.Scan(&spaceID, &rec.Purpose, &objectID, &rec.BucketID, &rec.ExpectedSize); err != nil {
			_ = rows.Close()
			return stacktrace.Propagate(err, "")
		}
		rec.ObjectKey = ProfileAssetObjectKey(spaceID, rec.Purpose, objectID)
		records = append(records, rec)
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return stacktrace.Propagate(err, "")
	}
	if err := rows.Close(); err != nil {
		return stacktrace.Propagate(err, "")
	}
	for _, rec := range records {
		if err := QueueObjectCleanupTx(ctx, tx, rec); err != nil {
			return err
		}
	}
	return nil
}

func queuePostObjectsTx(ctx context.Context, tx *sql.Tx, spaceIDs []string) error {
	rows, err := tx.QueryContext(ctx, `
		SELECT a.object_key, a.bucket_id, COALESCE(NULLIF(a.size, 0), 1)
		FROM space_post_assets a
		JOIN space_posts p ON p.post_id = a.post_id
		WHERE p.space_id = ANY($1)
	`, pq.Array(spaceIDs))
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	records := make([]SpaceTempObjectRecord, 0)
	for rows.Next() {
		rec := SpaceTempObjectRecord{
			Purpose: TempObjectPurposePost,
		}
		if err := rows.Scan(&rec.ObjectKey, &rec.BucketID, &rec.ExpectedSize); err != nil {
			_ = rows.Close()
			return stacktrace.Propagate(err, "")
		}
		records = append(records, rec)
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return stacktrace.Propagate(err, "")
	}
	if err := rows.Close(); err != nil {
		return stacktrace.Propagate(err, "")
	}
	for _, rec := range records {
		if err := QueueObjectCleanupTx(ctx, tx, rec); err != nil {
			return err
		}
	}
	return nil
}

func deleteSpaceRowsTx(ctx context.Context, tx *sql.Tx, userID int64, spaceIDs []string) error {
	if err := resetSpaceAccessTx(ctx, tx, userID, spaceIDs); err != nil {
		return err
	}
	spaceIDArray := pq.Array(spaceIDs)
	if _, err := tx.ExecContext(ctx, `
		DELETE FROM space_messages
		WHERE sender_space_id = ANY($1)
		   OR recipient_space_id = ANY($1)
	`, spaceIDArray); err != nil {
		return stacktrace.Propagate(err, "failed to delete space messages")
	}
	if _, err := tx.ExecContext(ctx, `
		DELETE FROM space_post_assets
		WHERE post_id IN (
			SELECT post_id
			FROM space_posts
			WHERE space_id = ANY($1)
		)
	`, spaceIDArray); err != nil {
		return stacktrace.Propagate(err, "failed to delete space post assets")
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM space_posts WHERE space_id = ANY($1)`, spaceIDArray); err != nil {
		return stacktrace.Propagate(err, "failed to delete space posts")
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM space_key_versions WHERE space_id = ANY($1)`, spaceIDArray); err != nil {
		return stacktrace.Propagate(err, "failed to delete space key versions")
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM spaces WHERE owner_id = $1`, userID); err != nil {
		return stacktrace.Propagate(err, "failed to delete spaces")
	}
	return nil
}
