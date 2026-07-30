package repo

import (
	"context"
	"database/sql"
	"strings"

	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

type notificationReadMarkerExecer interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
}

func (r *ReadMarkersRepository) UpsertNotificationReadMarker(ctx context.Context, viewerSpaceID string, friendSpaceID string, readAt int64) error {
	return upsertNotificationReadMarker(ctx, r.DB, viewerSpaceID, friendSpaceID, readAt)
}

func upsertNotificationReadMarker(ctx context.Context, execer notificationReadMarkerExecer, viewerSpaceID string, friendSpaceID string, readAt int64) error {
	viewerSpaceID = strings.TrimSpace(viewerSpaceID)
	friendSpaceID = strings.TrimSpace(friendSpaceID)
	if viewerSpaceID == "" || friendSpaceID == "" || readAt <= 0 {
		return nil
	}
	_, err := execer.ExecContext(ctx, `
		INSERT INTO space_notification_read_markers (viewer_space_id, friend_space_id, read_at)
		VALUES ($1, $2, $3)
		ON CONFLICT (viewer_space_id, friend_space_id) DO UPDATE
		SET read_at = GREATEST(
			space_notification_read_markers.read_at,
			EXCLUDED.read_at
		)
	`, viewerSpaceID, friendSpaceID, readAt)
	return stacktrace.Propagate(err, "")
}

func (r *ReadMarkersRepository) GetLatestConversationActivityAt(ctx context.Context, viewerSpaceID string, friendSpaceID string) (int64, error) {
	viewerSpaceID = strings.TrimSpace(viewerSpaceID)
	friendSpaceID = strings.TrimSpace(friendSpaceID)
	if viewerSpaceID == "" || friendSpaceID == "" {
		return 0, nil
	}
	var readAt int64
	if err := r.DB.QueryRowContext(ctx, `
		SELECT activity_created_at
		FROM (`+chatSummaryActivityRowsSQL+`) activity
		LIMIT 1
	`, viewerSpaceID, pq.Array([]string{friendSpaceID})).Scan(&readAt); err != nil {
		if err == sql.ErrNoRows {
			return 0, nil
		}
		return 0, stacktrace.Propagate(err, "")
	}
	return readAt, nil
}

func (r *ReadMarkersRepository) HasUnreadNotifications(ctx context.Context, viewerSpaceID string) (bool, error) {
	var exists bool
	if err := r.DB.QueryRowContext(ctx, `
		SELECT EXISTS (
			SELECT 1
			FROM (`+currentFriendActivityRowsSQL+`) activity
			LEFT JOIN space_notification_read_markers nrm
			  ON nrm.viewer_space_id = $1
			 AND nrm.friend_space_id = activity.friend_space_id
			WHERE activity.notification_created_at > COALESCE(nrm.read_at, 0)
			LIMIT 1
			) OR EXISTS (
				SELECT 1
				FROM space_friend_requests fr
				JOIN spaces requester_space ON requester_space.space_id = fr.requester_space_id
				JOIN users requester_owner ON requester_owner.user_id = requester_space.owner_id AND requester_owner.encrypted_email IS NOT NULL
				WHERE fr.target_space_id = $1
				LIMIT 1
			)
	`, strings.TrimSpace(viewerSpaceID)).Scan(&exists); err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	return exists, nil
}
