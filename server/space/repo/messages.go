package repo

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strconv"
	"strings"

	"github.com/ente/museum/ente/base"
	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

const MaxActiveMessagesSentPerSpace = 5000

var ErrSpaceMessageLimitReached = errors.New("space message limit reached")

const spaceMessageBaseSelectColumns = `
	m.message_id,
	m.kind,
	m.sender_space_id,
	m.recipient_space_id,
	COALESCE(m.message_cipher, '\x'::bytea),
	%[2]s AS encrypted_message_key,
	m.reply_post_id,
	m.reply_message_id,
	(m.recipient_liked_at IS NOT NULL) AS liked,
	(m.recipient_liked_at IS NOT NULL AND m.recipient_space_id = %[1]s) AS viewer_liked,
	m.is_deleted,
	m.created_at,
	m.updated_at,
	CASE
		WHEN m.kind = 'post_like' AND m.sender_space_id = %[1]s THEN 'You liked a post'
		WHEN m.kind = 'post_like' THEN 'Liked your post'
		WHEN m.kind = 'friend_added' THEN 'You are now friends'
		ELSE ''
	END AS text
`

func spaceMessageSelectColumns(viewerPlaceholder string) string {
	encryptedMessageKeySQL := `
		CASE
			WHEN m.sender_space_id = ` + viewerPlaceholder + ` THEN COALESCE(m.sender_encrypted_message_key, '\x'::bytea)
			ELSE COALESCE(m.recipient_encrypted_message_key, '\x'::bytea)
		END`
	return strings.TrimSpace(fmt.Sprintf(spaceMessageBaseSelectColumns, viewerPlaceholder, encryptedMessageKeySQL))
}

const selectedThreadKeySQL = `CASE WHEN $1 < $2 THEN $1 || ':' || $2 ELSE $2 || ':' || $1 END`

const inputConversationPeersSQL = `
WITH conversation_peers AS (
	SELECT DISTINCT input_friend.friend_space_id
	FROM unnest($2::text[]) AS input_friend(friend_space_id)
	WHERE input_friend.friend_space_id <> ''
)`

const currentFriendConversationPeersSQL = `
WITH conversation_peers AS (
	SELECT DISTINCT s.friend_space_id
	FROM space_friend_shares s
	JOIN spaces friend_space ON friend_space.space_id = s.friend_space_id
	JOIN users friend_owner ON friend_owner.user_id = friend_space.owner_id AND friend_owner.encrypted_email IS NOT NULL
	WHERE s.space_id = $1
)`

const conversationActivityRowsSQL = `,
peer_messages AS (
	SELECT m.*
	FROM space_messages m
	JOIN conversation_peers cp
	  ON (
	      (m.sender_space_id = $1 AND m.recipient_space_id = cp.friend_space_id)
	      OR (m.recipient_space_id = $1 AND m.sender_space_id = cp.friend_space_id)
	  )
	WHERE m.is_deleted = FALSE
)
SELECT
	friend_space_id,
	activity_type,
	activity_id,
	activity_created_at,
	is_outgoing,
	message_id,
	post_id,
	post_space_id,
	message_kind,
	sender_space_id,
	recipient_space_id,
	message_cipher,
	encrypted_message_key,
	reply_message_id,
	notification_created_at
FROM (
	SELECT
		CASE
			WHEN m.sender_space_id = $1 THEN m.recipient_space_id
			ELSE m.sender_space_id
		END AS friend_space_id,
		CASE
			WHEN m.kind = 'post_like' THEN 'post_like'
			WHEN m.kind = 'friend_added' THEN 'friend_added'
			WHEN m.kind = 'post_reply' AND m.recipient_space_id = $1 THEN 'post_reply'
			ELSE 'message'
		END AS activity_type,
		CASE
			WHEN m.kind = 'post_like' THEN 'post_like:' || m.reply_post_id || ':' || m.sender_space_id
			WHEN m.kind = 'friend_added' THEN 'friend_added:' || m.message_id
			WHEN m.kind = 'post_reply' AND m.recipient_space_id = $1 THEN 'post_reply:' || m.message_id
			ELSE 'message:' || m.message_id
		END AS activity_id,
		m.created_at AS activity_created_at,
		CASE WHEN m.kind = 'post_like' THEN NULL::text ELSE m.message_id END AS message_id,
		m.reply_post_id AS post_id,
		m.recipient_space_id AS post_space_id,
		m.kind AS message_kind,
		m.sender_space_id,
		m.recipient_space_id,
		m.message_cipher,
		CASE
			WHEN m.sender_space_id = $1 THEN m.sender_encrypted_message_key
			ELSE m.recipient_encrypted_message_key
		END AS encrypted_message_key,
		m.reply_message_id,
		CASE
			WHEN m.recipient_space_id = $1 AND m.kind IN ('regular', 'post_reply', 'post_like', 'friend_added') THEN m.created_at
			ELSE NULL::bigint
		END AS notification_created_at,
		(m.sender_space_id = $1) AS is_outgoing
	FROM peer_messages m
	WHERE m.kind IN ('regular', 'post_reply', 'post_like', 'friend_added')

	UNION ALL

	SELECT
		CASE
			WHEN m.sender_space_id = $1 THEN m.recipient_space_id
			ELSE m.sender_space_id
		END AS friend_space_id,
		'message_like' AS activity_type,
		'message_like:' || m.message_id || ':' || m.recipient_space_id AS activity_id,
		m.recipient_liked_at AS activity_created_at,
		m.message_id,
		NULL::bigint AS post_id,
		NULL::text AS post_space_id,
		m.kind AS message_kind,
		m.sender_space_id,
		m.recipient_space_id,
		m.message_cipher,
		CASE
			WHEN m.sender_space_id = $1 THEN m.sender_encrypted_message_key
			ELSE m.recipient_encrypted_message_key
		END AS encrypted_message_key,
		m.reply_message_id,
		CASE WHEN m.sender_space_id = $1 THEN m.recipient_liked_at ELSE NULL::bigint END AS notification_created_at,
		(m.recipient_space_id = $1) AS is_outgoing
	FROM peer_messages m
	WHERE m.kind IN ('regular', 'post_reply')
	  AND m.recipient_liked_at IS NOT NULL
) activity`

const chatSummaryActivityRowsSQL = inputConversationPeersSQL + conversationActivityRowsSQL + `
ORDER BY friend_space_id, activity_created_at DESC, activity_id DESC`

const currentFriendActivityRowsSQL = currentFriendConversationPeersSQL + conversationActivityRowsSQL

func (r *MessagesRepository) CreateMessage(ctx context.Context, input CreateSpaceMessageRecord) (*SpaceMessageRecord, error) {
	messageID := strings.TrimSpace(input.MessageID)
	if messageID == "" {
		messageID = base.MustNewID("wmsg")
	}
	var replyPostID any
	if input.ReplyPostID.Valid {
		replyPostID = input.ReplyPostID.Int64
	}
	var replyMessageID any
	if input.ReplyMessageID.Valid {
		replyMessageID = input.ReplyMessageID.String
	}
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()
	var senderSpaceID string
	if err := tx.QueryRowContext(ctx, `
		SELECT space_id
		FROM spaces
		WHERE space_id = $1
		FOR UPDATE
	`, input.SenderSpaceID).Scan(&senderSpaceID); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	var activeMessageCount int
	if err := tx.QueryRowContext(ctx, `
		SELECT COUNT(*)
		FROM space_messages
		WHERE sender_space_id = $1
		  AND kind IN ('regular', 'post_reply')
		  AND is_deleted = FALSE
	`, senderSpaceID).Scan(&activeMessageCount); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if activeMessageCount >= MaxActiveMessagesSentPerSpace {
		return nil, ErrSpaceMessageLimitReached
	}
	var createdAt int64
	var updatedAt int64
	if err := tx.QueryRowContext(ctx, `
		INSERT INTO space_messages (
			message_id,
			sender_space_id,
			recipient_space_id,
			kind,
			message_cipher,
			sender_encrypted_message_key,
			recipient_encrypted_message_key,
			reply_post_id,
			reply_message_id
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		RETURNING created_at, updated_at
	`, messageID, input.SenderSpaceID, input.RecipientSpaceID, input.Kind, input.MessageCipher, input.SenderEncryptedMessageKey, input.RecipientEncryptedMessageKey, replyPostID, replyMessageID).Scan(&createdAt, &updatedAt); err != nil {
		return nil, wrapUnique(err, "message already exists")
	}
	if err := tx.Commit(); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &SpaceMessageRecord{
		MessageID:           messageID,
		Kind:                input.Kind,
		SenderSpaceID:       input.SenderSpaceID,
		RecipientSpaceID:    input.RecipientSpaceID,
		MessageCipher:       input.MessageCipher,
		EncryptedMessageKey: input.SenderEncryptedMessageKey,
		ReplyPostID:         input.ReplyPostID,
		ReplyMessageID:      input.ReplyMessageID,
		CreatedAt:           createdAt,
		UpdatedAt:           updatedAt,
	}, nil
}

func (r *MessagesRepository) GetMessage(ctx context.Context, messageID string, viewerSpaceID string) (*SpaceMessageRecord, error) {
	query := `
		SELECT ` + spaceMessageSelectColumns("$2") + `
		FROM space_messages m
		WHERE m.message_id = $1
		  AND (m.sender_space_id = $2 OR m.recipient_space_id = $2)
	`
	return scanMessageRecord(r.DB.QueryRowContext(ctx, query, messageID, viewerSpaceID))
}

func (r *MessagesRepository) ListThread(ctx context.Context, viewerSpaceID string, otherSpaceID string, cursor string, limit int) ([]SpaceMessageRecord, string, error) {
	limit = optionalInt(limit, 50)
	if limit > 100 {
		limit = 100
	}
	args := []any{viewerSpaceID, otherSpaceID}
	query := `
		SELECT ` + spaceMessageSelectColumns("$1") + `
		FROM space_messages m
		WHERE m.thread_key = ` + selectedThreadKeySQL + `
		  AND m.is_deleted = FALSE`
	if cursorCreatedAt, cursorMessageID, ok := parseMessageCursor(cursor); ok {
		args = append(args, cursorCreatedAt, cursorMessageID)
		query += ` AND (m.created_at, m.message_id) < ($3, $4)`
	}
	args = append(args, limit+1)
	query += ` ORDER BY m.created_at DESC, m.message_id DESC LIMIT $` + strconv.Itoa(len(args))
	rows, err := r.DB.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, "", stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	out := make([]SpaceMessageRecord, 0, limit+1)
	for rows.Next() {
		rec, err := scanMessageRecord(rows)
		if err != nil {
			return nil, "", err
		}
		out = append(out, *rec)
	}
	if err := rows.Err(); err != nil {
		return nil, "", stacktrace.Propagate(err, "")
	}
	nextCursor := ""
	if len(out) > limit {
		nextCursor = formatMessageCursor(out[limit-1])
		out = out[:limit]
	}
	return out, nextCursor, nil
}

func (r *MessagesRepository) SetLike(ctx context.Context, messageID string, actorSpaceID string, like bool) error {
	if like {
		_, err := r.DB.ExecContext(ctx, `
			UPDATE space_messages
			SET recipient_liked_at = COALESCE(recipient_liked_at, now_utc_micro_seconds())
			WHERE message_id = $1
			  AND recipient_space_id = $2
			  AND kind IN ('regular', 'post_reply')
			  AND is_deleted = FALSE
		`, messageID, actorSpaceID)
		return stacktrace.Propagate(err, "")
	}
	_, err := r.DB.ExecContext(ctx, `
		UPDATE space_messages
		SET recipient_liked_at = NULL
		WHERE message_id = $1
		  AND recipient_space_id = $2
		  AND kind IN ('regular', 'post_reply')
	`, messageID, actorSpaceID)
	return stacktrace.Propagate(err, "")
}

func (r *MessagesRepository) DeleteMessage(ctx context.Context, messageID string, senderSpaceID string) error {
	res, err := r.DB.ExecContext(ctx, `
		UPDATE space_messages
		SET is_deleted = TRUE
		WHERE message_id = $1
		  AND sender_space_id = $2
		  AND kind IN ('regular', 'post_reply')
		  AND is_deleted = FALSE
	`, messageID, senderSpaceID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if affected == 0 {
		return sql.ErrNoRows
	}
	return nil
}

func (r *MessagesRepository) ListLatestChatSummaries(ctx context.Context, viewerSpaceID string, friendSpaceIDs []string) (map[string]SpaceConversationChatSummaryRecord, error) {
	cleanFriendSpaceIDs := make([]string, 0, len(friendSpaceIDs))
	for _, friendSpaceID := range friendSpaceIDs {
		friendSpaceID = strings.TrimSpace(friendSpaceID)
		if friendSpaceID != "" {
			cleanFriendSpaceIDs = append(cleanFriendSpaceIDs, friendSpaceID)
		}
	}
	out := make(map[string]SpaceConversationChatSummaryRecord, len(cleanFriendSpaceIDs))
	if len(cleanFriendSpaceIDs) == 0 {
		return out, nil
	}
	readMarkers, err := r.listNotificationReadMarkers(ctx, viewerSpaceID, cleanFriendSpaceIDs)
	if err != nil {
		return nil, err
	}
	rows, err := r.DB.QueryContext(ctx, chatSummaryActivityRowsSQL, strings.TrimSpace(viewerSpaceID), pq.Array(cleanFriendSpaceIDs))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	for rows.Next() {
		friendSpaceID, activity, notificationCreatedAt, err := scanConversationActivityRow(rows)
		if err != nil {
			return nil, err
		}
		summary := out[friendSpaceID]
		if summary.FriendSpaceID == "" {
			summary.FriendSpaceID = friendSpaceID
			summary.LatestActivity = activity
		}
		if notificationCreatedAt.Valid && notificationCreatedAt.Int64 > readMarkers[friendSpaceID] {
			activity.Kind = sql.NullString{}
			activity.SenderSpaceID = sql.NullString{}
			activity.RecipientSpaceID = sql.NullString{}
			activity.MessageCipher = nil
			activity.EncryptedMessageKey = nil
			activity.ReplyMessageID = sql.NullString{}
			summary.UnreadActivities = append(summary.UnreadActivities, activity)
		}
		out[friendSpaceID] = summary
	}
	if err := rows.Err(); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return out, nil
}

func (r *MessagesRepository) listNotificationReadMarkers(ctx context.Context, viewerSpaceID string, friendSpaceIDs []string) (map[string]int64, error) {
	out := make(map[string]int64, len(friendSpaceIDs))
	rows, err := r.DB.QueryContext(ctx, `
		SELECT friend_space_id, read_at
		FROM space_notification_read_markers
		WHERE viewer_space_id = $1
		  AND friend_space_id = ANY($2)
	`, strings.TrimSpace(viewerSpaceID), pq.Array(friendSpaceIDs))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	for rows.Next() {
		var friendSpaceID string
		var readAt int64
		if err := rows.Scan(&friendSpaceID, &readAt); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		out[friendSpaceID] = readAt
	}
	return out, stacktrace.Propagate(rows.Err(), "")
}

func scanMessageRecord(scanner interface{ Scan(dest ...any) error }) (*SpaceMessageRecord, error) {
	var rec SpaceMessageRecord
	dest := []any{
		&rec.MessageID,
		&rec.Kind,
		&rec.SenderSpaceID,
		&rec.RecipientSpaceID,
		&rec.MessageCipher,
		&rec.EncryptedMessageKey,
		&rec.ReplyPostID,
		&rec.ReplyMessageID,
		&rec.Liked,
		&rec.ViewerLiked,
		&rec.IsDeleted,
		&rec.CreatedAt,
		&rec.UpdatedAt,
		&rec.Text,
	}
	if err := scanner.Scan(dest...); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &rec, nil
}

func scanConversationActivityRow(scanner interface{ Scan(dest ...any) error }) (string, SpaceMessageConversationActivityRecord, sql.NullInt64, error) {
	var friendSpaceID string
	var activity SpaceMessageConversationActivityRecord
	var notificationCreatedAt sql.NullInt64
	dest := []any{&friendSpaceID}
	dest = append(dest, conversationActivityScanDest(&activity)...)
	dest = append(dest, &notificationCreatedAt)
	if err := scanner.Scan(dest...); err != nil {
		return "", SpaceMessageConversationActivityRecord{}, sql.NullInt64{}, stacktrace.Propagate(err, "")
	}
	return friendSpaceID, activity, notificationCreatedAt, nil
}

func conversationActivityScanDest(activity *SpaceMessageConversationActivityRecord) []any {
	return []any{
		&activity.Type,
		&activity.ID,
		&activity.CreatedAt,
		&activity.Outgoing,
		&activity.MessageID,
		&activity.PostID,
		&activity.PostSpaceID,
		&activity.Kind,
		&activity.SenderSpaceID,
		&activity.RecipientSpaceID,
		&activity.MessageCipher,
		&activity.EncryptedMessageKey,
		&activity.ReplyMessageID,
	}
}

func parseMessageCursor(cursor string) (int64, string, bool) {
	createdAtText, id, ok := strings.Cut(strings.TrimSpace(cursor), ":")
	if !ok || strings.TrimSpace(id) == "" {
		return 0, "", false
	}
	createdAt, err := strconv.ParseInt(createdAtText, 10, 64)
	if err != nil || createdAt <= 0 {
		return 0, "", false
	}
	return createdAt, id, true
}

func formatMessageCursor(message SpaceMessageRecord) string {
	return strconv.FormatInt(message.CreatedAt, 10) + ":" + message.MessageID
}
