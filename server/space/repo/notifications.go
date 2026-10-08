package repo

import (
	"context"
	"database/sql"
	"strconv"

	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

type NotificationsRepository struct {
	DB *sql.DB
}

type SpaceNotificationRecord struct {
	NotificationID  string
	Kind            string
	Actors          []SpaceActorRecord
	ActorCount      int64
	PostID          sql.NullInt64
	FriendRequestID sql.NullInt64
	CreatedAt       int64
	Unread          bool
}

const notificationSourcesSQL = `
	FROM space_notifications n
	LEFT JOIN space_post_likes l ON l.like_id = n.post_like_id
	LEFT JOIN space_posts p ON p.post_id = l.post_id AND p.is_deleted = FALSE
	JOIN spaces actor ON actor.space_id = n.actor_space_id
	JOIN users actor_owner ON actor_owner.user_id = actor.owner_id AND actor_owner.encrypted_email IS NOT NULL
`

const notificationVisibleSQL = `
	(n.kind = 'friend_request' OR (
		(n.kind IN ('friend_accepted', 'poke') OR p.post_id IS NOT NULL)
		AND EXISTS (SELECT 1 FROM space_friend_shares share
			WHERE share.space_id = n.recipient_space_id AND share.friend_space_id = n.actor_space_id)
	))
`

func (r *NotificationsRepository) List(ctx context.Context, recipientSpaceID, cursor string, limit int) ([]SpaceNotificationRecord, string, error) {
	limit = optionalInt(limit, 50)
	if limit > 100 {
		limit = 100
	}
	query := `WITH visible AS (
		SELECT n.*, l.post_id, CASE
			WHEN n.kind = 'post_like' THEN l.post_id::text
			WHEN n.kind IN ('friend_accepted', 'poke') THEN n.actor_space_id
			ELSE n.notification_id
		END AS group_id
		` + notificationSourcesSQL + ` WHERE n.recipient_space_id = $1 AND ` + notificationVisibleSQL + `
	), ranked AS (
		SELECT notification_id, kind, actor_space_id, post_id, friend_request_id, created_at, group_id,
			CASE WHEN kind = 'post_like' THEN COUNT(*) OVER (PARTITION BY kind, group_id) ELSE 1 END AS actor_count,
			BOOL_OR(read_at IS NULL) OVER (PARTITION BY kind, group_id) AS unread,
			ROW_NUMBER() OVER (PARTITION BY kind, group_id ORDER BY created_at DESC, notification_id DESC) AS position
		FROM visible
	), page AS (
		SELECT * FROM ranked WHERE position = 1`
	args := []any{recipientSpaceID}
	if createdAt, id, ok := parseMessageCursor(cursor); ok {
		query += ` AND (created_at, notification_id) < ($2, $3)`
		args = append(args, createdAt, id)
	}
	args = append(args, limit+1)
	query += ` ORDER BY created_at DESC, notification_id DESC LIMIT $` + strconv.Itoa(len(args)) + `
	)
	SELECT page.notification_id, page.kind, page.post_id, page.friend_request_id, page.created_at, page.actor_count, page.unread, ` + spaceActorSelectColumns("actor", "avatar", "actor") + `
	FROM page
	JOIN ranked sample ON sample.kind = page.kind AND sample.group_id = page.group_id
		AND sample.position <= CASE WHEN page.kind = 'post_like' THEN 2 ELSE 1 END
	JOIN spaces actor ON actor.space_id = sample.actor_space_id
	` + spaceActorAvatarJoin("actor", "avatar") + `
	ORDER BY page.created_at DESC, page.notification_id DESC, sample.position`
	rows, err := r.DB.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, "", stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	items := make([]SpaceNotificationRecord, 0)
	for rows.Next() {
		var item SpaceNotificationRecord
		var actor SpaceActorRecord
		dest := []any{&item.NotificationID, &item.Kind, &item.PostID, &item.FriendRequestID, &item.CreatedAt, &item.ActorCount, &item.Unread}
		dest = append(dest, spaceActorScanDest(&actor)...)
		if err := rows.Scan(dest...); err != nil {
			return nil, "", stacktrace.Propagate(err, "")
		}
		if len(items) == 0 || items[len(items)-1].NotificationID != item.NotificationID {
			items = append(items, item)
		}
		last := &items[len(items)-1]
		last.Actors = append(last.Actors, actor)
	}
	if err := rows.Err(); err != nil {
		return nil, "", stacktrace.Propagate(err, "")
	}
	nextCursor := ""
	if len(items) > limit {
		last := items[limit-1]
		nextCursor = strconv.FormatInt(last.CreatedAt, 10) + ":" + last.NotificationID
		items = items[:limit]
	}
	return items, nextCursor, nil
}

func (r *NotificationsRepository) HasUnread(ctx context.Context, recipientSpaceID string) (bool, error) {
	var unread bool
	err := r.DB.QueryRowContext(ctx, `SELECT EXISTS (SELECT 1 `+notificationSourcesSQL+` WHERE n.recipient_space_id = $1 AND n.read_at IS NULL AND `+notificationVisibleSQL+`)`, recipientSpaceID).Scan(&unread)
	return unread, stacktrace.Propagate(err, "")
}

func (r *NotificationsRepository) MarkRead(ctx context.Context, recipientSpaceID string, notificationIDs []string) error {
	_, err := r.DB.ExecContext(ctx, `
		WITH visible AS (
			SELECT n.notification_id, n.kind, n.actor_space_id, l.post_id, n.created_at
			`+notificationSourcesSQL+` WHERE n.recipient_space_id = $1 AND `+notificationVisibleSQL+`
		)
		UPDATE space_notifications n SET read_at = now_utc_micro_seconds()
		FROM visible item, visible anchor
		WHERE n.notification_id = item.notification_id AND n.read_at IS NULL
			AND anchor.notification_id = ANY($2)
			AND (item.notification_id = anchor.notification_id OR (
				item.kind = anchor.kind AND (
					(item.kind = 'post_like' AND item.post_id = anchor.post_id)
					OR (item.kind IN ('friend_accepted', 'poke') AND item.actor_space_id = anchor.actor_space_id)
				)
				AND (item.created_at, item.notification_id) <= (anchor.created_at, anchor.notification_id)
			))
	`, recipientSpaceID, pq.Array(notificationIDs))
	return stacktrace.Propagate(err, "")
}
