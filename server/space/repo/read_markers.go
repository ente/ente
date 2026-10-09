package repo

import (
	"context"
	"database/sql"
	"strconv"
	"strings"

	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

type SpaceUnreadActivityRecord struct {
	MessageID           string
	Kind                string
	MessageCipher       []byte
	EncryptedMessageKey []byte
	CreatedAt           int64
}

func (r *ReadMarkersRepository) ListUnreadActivities(ctx context.Context, viewerSpaceID, cursor string, limit int) ([]SpaceUnreadActivityRecord, string, error) {
	limit = optionalInt(limit, 50)
	if limit > 100 {
		limit = 100
	}
	query := `WITH unread AS (
		SELECT m.message_id, m.kind, m.message_cipher,
			CASE WHEN m.sender_space_id = $1 THEN m.sender_encrypted_message_key ELSE m.recipient_encrypted_message_key END AS encrypted_message_key,
			CASE WHEN m.recipient_space_id = $1 THEN m.created_at ELSE m.recipient_liked_at END AS created_at
		FROM space_messages m
		JOIN space_friend_shares share ON share.space_id = $1
			AND share.friend_space_id = CASE WHEN m.sender_space_id = $1 THEN m.recipient_space_id ELSE m.sender_space_id END
		JOIN spaces friend ON friend.space_id = share.friend_space_id
		JOIN users friend_owner ON friend_owner.user_id = friend.owner_id AND friend_owner.encrypted_email IS NOT NULL
		LEFT JOIN space_notification_read_markers marker ON marker.viewer_space_id = $1 AND marker.friend_space_id = share.friend_space_id
		WHERE m.is_deleted = FALSE AND m.kind IN ('regular', 'post_reply')
			AND ((m.recipient_space_id = $1 AND m.created_at > COALESCE(marker.read_at, 0))
				OR (m.sender_space_id = $1 AND m.recipient_liked_at > COALESCE(marker.read_at, 0)))
	)
	SELECT message_id, kind, message_cipher, encrypted_message_key, created_at FROM unread`
	args := []any{viewerSpaceID}
	if createdAt, id, ok := parseMessageCursor(cursor); ok {
		query += ` WHERE (created_at, message_id) < ($2, $3)`
		args = append(args, createdAt, id)
	}
	args = append(args, limit+1)
	query += ` ORDER BY created_at DESC, message_id DESC LIMIT $` + strconv.Itoa(len(args))
	rows, err := r.DB.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, "", stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	items := make([]SpaceUnreadActivityRecord, 0)
	for rows.Next() {
		var item SpaceUnreadActivityRecord
		if err := rows.Scan(&item.MessageID, &item.Kind, &item.MessageCipher, &item.EncryptedMessageKey, &item.CreatedAt); err != nil {
			return nil, "", stacktrace.Propagate(err, "")
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, "", stacktrace.Propagate(err, "")
	}
	nextCursor := ""
	if len(items) > limit {
		last := items[limit-1]
		nextCursor = strconv.FormatInt(last.CreatedAt, 10) + ":" + last.MessageID
		items = items[:limit]
	}
	return items, nextCursor, nil
}

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
			)
	`, strings.TrimSpace(viewerSpaceID)).Scan(&exists); err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	return exists, nil
}
