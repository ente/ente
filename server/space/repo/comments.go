package repo

import (
	"context"
	"database/sql"
	"strconv"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/base"
	"github.com/ente/museum/space/models"
	"github.com/lib/pq"
)

type CommentsRepository struct{ DB *sql.DB }

type CommentRecord struct {
	ID                    string
	Author                SpaceActorRecord
	Private               bool
	ParentID              string
	ReplyToID             string
	Cipher                []byte
	CreatedAt             int64
	CanDelete             bool
	Reactions             []CommentReactionRecord
	UnreadNotificationIDs []string
}

type CommentReactionRecord struct {
	Actor   SpaceActorRecord
	Private bool
	Cipher  []byte
}

type CommentNotificationRecipient struct {
	UserID int64
	Kind   string
}

const discussionAccessSQL = `(p.space_id = $2 OR EXISTS (SELECT 1 FROM space_friend_shares f WHERE f.space_id = p.space_id AND f.friend_space_id = $2))`

const commentVisibleSQL = `NOT EXISTS (
    WITH RECURSIVE ancestors AS (
        SELECT c.reply_to_id, c.author_space_id, c.cipher IS NOT NULL AS has_content
        UNION ALL
        SELECT parent.reply_to_id, parent.author_space_id, parent.cipher IS NOT NULL
        FROM space_comments parent JOIN ancestors child ON parent.comment_id = child.reply_to_id
    )
    SELECT 1 FROM ancestors a
    LEFT JOIN spaces author ON author.space_id = a.author_space_id
    LEFT JOIN users account ON account.user_id = author.owner_id
    WHERE NOT a.has_content OR account.encrypted_email IS NULL
)`

const commentNotHiddenSQL = `NOT EXISTS (
    SELECT 1 FROM hidden_comments hidden WHERE hidden.comment_id = c.comment_id
)`

func hiddenCommentsCTE(postFilter string) string {
	return `hidden_comments AS (
    SELECT c.comment_id, c.post_id FROM space_comments c
    LEFT JOIN spaces author ON author.space_id = c.author_space_id
    LEFT JOIN users account ON account.user_id = author.owner_id
    WHERE ` + postFilter + ` AND (c.cipher IS NULL OR account.encrypted_email IS NULL)
    UNION
    SELECT child.comment_id, parent.post_id FROM hidden_comments parent
    CROSS JOIN LATERAL (
        SELECT c.comment_id FROM space_comments c
        WHERE c.reply_to_id = parent.comment_id AND c.post_id = parent.post_id
        OFFSET 0
    ) child
)`
}

var commentRecipientsSQL = `WITH RECURSIVE ` + hiddenCommentsCTE("c.post_id = $2") + `
SELECT ARRAY(
    SELECT participant.space_id FROM (
        SELECT $1::text AS space_id
        UNION
        SELECT c.author_space_id FROM space_comments c WHERE c.post_id = $2 AND ` + commentNotHiddenSQL + `
        UNION
        SELECT l.actor_space_id FROM space_post_likes l WHERE l.post_id = $2
    ) participant
    JOIN spaces s ON s.space_id = participant.space_id
    JOIN users u ON u.user_id = s.owner_id AND u.encrypted_email IS NOT NULL
    WHERE participant.space_id <> $3
)`

func discussionPostTx(ctx context.Context, tx *sql.Tx, viewer string, postID int64, forUpdate bool) (string, error) {
	locking := "FOR SHARE OF s, p"
	if forUpdate {
		locking = "FOR SHARE OF s FOR UPDATE OF p"
	}
	var owner string
	err := tx.QueryRowContext(ctx, `SELECT s.space_id FROM space_posts p
        JOIN spaces s ON s.space_id = p.space_id WHERE p.post_id = $1 AND NOT p.is_deleted `+locking, postID).Scan(&owner)
	if err != nil {
		return "", err
	}
	if owner != viewer {
		var friend string
		if err := tx.QueryRowContext(ctx, `SELECT friend_space_id FROM space_friend_shares
            WHERE space_id = $1 AND friend_space_id = $2 FOR SHARE`, owner, viewer).Scan(&friend); err != nil {
			return "", err
		}
	}
	var allowed bool
	err = tx.QueryRowContext(ctx, `SELECT EXISTS (SELECT 1 FROM space_posts p JOIN spaces s ON s.space_id = p.space_id
        JOIN users u ON u.user_id = s.owner_id AND u.encrypted_email IS NOT NULL
        WHERE p.post_id = $1 AND NOT p.is_deleted AND `+discussionAccessSQL+`
        AND EXISTS (SELECT 1 FROM spaces viewer JOIN users viewer_owner ON viewer_owner.user_id = viewer.owner_id
            WHERE viewer.space_id = $2 AND viewer_owner.encrypted_email IS NOT NULL))`, postID, viewer).Scan(&allowed)
	if err != nil {
		return "", err
	}
	if !allowed {
		return "", sql.ErrNoRows
	}
	return owner, nil
}

func (r *CommentsRepository) List(ctx context.Context, viewer string, postID int64, cursor string) ([]CommentRecord, string, error) {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, "", err
	}
	defer tx.Rollback()
	owner, err := discussionPostTx(ctx, tx, viewer, postID, false)
	if err != nil {
		return nil, "", err
	}
	createdAt, id, _ := parseMessageCursor(cursor)
	rows, err := tx.QueryContext(ctx, `WITH RECURSIVE `+hiddenCommentsCTE("c.post_id = $1")+`
        SELECT c.comment_id, COALESCE(c.parent_id, ''), COALESCE(c.reply_to_id, ''),
        CASE WHEN `+commentNotHiddenSQL+` THEN c.cipher END, c.created_at,
        (COALESCE(actor.space_id = $2, FALSE) OR EXISTS (SELECT 1 FROM space_friend_shares f WHERE f.space_id = actor.space_id AND f.friend_space_id = $2)),
        COALESCE(actor.space_id, ''), COALESCE(actor.space_slug, ''), actor.public_key, COALESCE(actor.current_version, 0), actor.encrypted_profile,
        avatar.object_id, avatar.key_version, avatar.size, COALESCE(actor.updated_at, 0)
        FROM space_comments c LEFT JOIN spaces actor ON actor.space_id = c.author_space_id
        AND EXISTS (SELECT 1 FROM users u WHERE u.user_id = actor.owner_id AND u.encrypted_email IS NOT NULL) `+spaceActorAvatarJoin("actor", "avatar")+`
        WHERE c.post_id = $1 AND (c.created_at, c.comment_id) > ($3, $4) ORDER BY c.created_at, c.comment_id LIMIT 101`, postID, viewer, createdAt, id)
	if err != nil {
		return nil, "", err
	}
	items := make([]CommentRecord, 0)
	for rows.Next() {
		var item CommentRecord
		dest := []any{&item.ID, &item.ParentID, &item.ReplyToID, &item.Cipher, &item.CreatedAt, &item.Private}
		if err := rows.Scan(append(dest, spaceActorScanDest(&item.Author)...)...); err != nil {
			rows.Close()
			return nil, "", err
		}
		item.CanDelete = len(item.Cipher) > 0 && (item.Author.SpaceID == viewer || owner == viewer)
		item.Reactions = make([]CommentReactionRecord, 0)
		item.UnreadNotificationIDs = make([]string, 0)
		items = append(items, item)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return nil, "", err
	}
	next := ""
	if len(items) > 100 {
		items = items[:100]
		last := items[99]
		next = strconv.FormatInt(last.CreatedAt, 10) + ":" + last.ID
	}
	commentIDs := make([]string, 0, len(items))
	commentsByID := make(map[string]*CommentRecord, len(items))
	for i := range items {
		if len(items[i].Cipher) > 0 {
			commentIDs = append(commentIDs, items[i].ID)
			commentsByID[items[i].ID] = &items[i]
		}
	}
	rows, err = tx.QueryContext(ctx, `SELECT r.comment_id, r.cipher,
            (actor.space_id = $2 OR EXISTS (SELECT 1 FROM space_friend_shares f WHERE f.space_id = actor.space_id AND f.friend_space_id = $2)), `+spaceActorSelectColumns("actor", "avatar", "actor")+`
            FROM space_comment_reactions r JOIN spaces actor ON actor.space_id = r.actor_space_id
            JOIN users u ON u.user_id = actor.owner_id AND u.encrypted_email IS NOT NULL `+spaceActorAvatarJoin("actor", "avatar")+`
		WHERE r.comment_id = ANY($1) ORDER BY r.comment_id, r.actor_space_id`, pq.Array(commentIDs), viewer)
	if err != nil {
		return nil, "", err
	}
	defer rows.Close()
	for rows.Next() {
		var commentID string
		var reaction CommentReactionRecord
		dest := []any{&commentID, &reaction.Cipher, &reaction.Private}
		if err := rows.Scan(append(dest, spaceActorScanDest(&reaction.Actor)...)...); err != nil {
			return nil, "", err
		}
		comment := commentsByID[commentID]
		comment.Reactions = append(comment.Reactions, reaction)
	}
	if err := rows.Err(); err != nil {
		return nil, "", err
	}
	rows.Close()
	const unreadFilter = `n.recipient_space_id = $1 AND n.comment_id = ANY($2) AND n.read_at IS NULL`
	rows, err = tx.QueryContext(ctx, `WITH RECURSIVE `+notificationHiddenCommentsCTE(unreadFilter)+`
        SELECT n.comment_id, n.notification_id `+notificationSourcesSQL+`
        WHERE `+unreadFilter+` AND `+notificationVisibleSQL(commentNotHiddenSQL), viewer, pq.Array(commentIDs))
	if err != nil {
		return nil, "", err
	}
	defer rows.Close()
	for rows.Next() {
		var commentID, notificationID string
		if err := rows.Scan(&commentID, &notificationID); err != nil {
			return nil, "", err
		}
		comment := commentsByID[commentID]
		comment.UnreadNotificationIDs = append(comment.UnreadNotificationIDs, notificationID)
	}
	if err := rows.Err(); err != nil {
		return nil, "", err
	}
	return items, next, tx.Commit()
}

func (r *CommentsRepository) Create(ctx context.Context, viewer string, postID int64, req models.CreateCommentRequest, cipher []byte) error {
	_, err := r.CreateWithCreated(ctx, viewer, postID, req, cipher)
	return err
}

func (r *CommentsRepository) CreateWithCreated(ctx context.Context, viewer string, postID int64, req models.CreateCommentRequest, cipher []byte) (bool, error) {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return false, err
	}
	defer tx.Rollback()
	owner, err := discussionPostTx(ctx, tx, viewer, postID, true)
	if err != nil {
		return false, err
	}
	var matches bool
	err = tx.QueryRowContext(ctx, `SELECT post_id = $2 AND COALESCE(author_space_id, '') = $3 AND COALESCE(reply_to_id, '') = $4
        FROM space_comments WHERE comment_id = $1`, req.CommentID, postID, viewer, req.ReplyToID).Scan(&matches)
	if err == nil {
		if !matches {
			return false, ente.NewConflictError("comment ID already used")
		}
		return false, nil
	}
	if err != sql.ErrNoRows {
		return false, err
	}
	var parent, replyRecipient string
	if req.ReplyToID != "" {
		if err := tx.QueryRowContext(ctx, `SELECT COALESCE(c.parent_id, c.comment_id), c.author_space_id FROM space_comments c
            WHERE c.comment_id = $1 AND c.post_id = $2 AND `+commentVisibleSQL, req.ReplyToID, postID).Scan(&parent, &replyRecipient); err != nil {
			return false, err
		}
	}
	res, err := tx.ExecContext(ctx, `INSERT INTO space_comments (comment_id, post_id, author_space_id, parent_id, reply_to_id, cipher)
        VALUES ($1, $2, $3, NULLIF($4, ''), NULLIF($5, ''), $6) ON CONFLICT (comment_id) DO NOTHING`, req.CommentID, postID, viewer, parent, req.ReplyToID, cipher)
	if err != nil {
		return false, err
	}
	count, err := res.RowsAffected()
	if err != nil {
		return false, err
	}
	if count == 0 {
		return false, ente.NewConflictError("comment ID already used")
	}
	var recipients pq.StringArray
	if err := tx.QueryRowContext(ctx, commentRecipientsSQL, owner, postID, viewer).Scan(&recipients); err != nil {
		return false, err
	}
	for _, recipient := range recipients {
		kind := "comment"
		if recipient == replyRecipient {
			kind = "comment_reply"
		}
		if _, err := commentNotificationTx(ctx, tx, owner, viewer, recipient, req.CommentID, kind); err != nil {
			return false, err
		}
	}
	if err := tx.Commit(); err != nil {
		return false, err
	}
	return true, nil
}

func commentNotificationTx(ctx context.Context, tx *sql.Tx, owner, actor, recipient, commentID, kind string) (bool, error) {
	res, err := tx.ExecContext(ctx, `INSERT INTO space_notifications (notification_id, recipient_space_id, actor_space_id, kind, comment_id)
        SELECT $1, $2, $3, $4, $5 WHERE $2 <> $3 AND ($2 = $6 OR EXISTS (SELECT 1 FROM space_friend_shares WHERE space_id = $6 AND friend_space_id = $2))
        AND ($4 <> 'comment' OR $2 = $6 OR EXISTS (SELECT 1 FROM space_friend_shares WHERE space_id = $2 AND friend_space_id = $3))
        ON CONFLICT DO NOTHING`, base.MustNewID("wnot"), recipient, actor, kind, commentID, owner)
	if err != nil {
		return false, err
	}
	count, err := res.RowsAffected()
	return count > 0, err
}

func (r *CommentsRepository) Delete(ctx context.Context, viewer string, postID int64, commentID string) error {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	owner, err := discussionPostTx(ctx, tx, viewer, postID, true)
	if err != nil {
		return err
	}
	var deletedIDs pq.StringArray
	err = tx.QueryRowContext(ctx, `WITH RECURSIVE branch AS (
        SELECT comment_id FROM space_comments WHERE comment_id = $1 AND post_id = $2
        AND (author_space_id = $3 OR $3 = $4)
        UNION ALL
        SELECT c.comment_id FROM space_comments c JOIN branch parent ON c.reply_to_id = parent.comment_id
        WHERE c.post_id = $2
    ), removed AS (
        UPDATE space_comments c SET cipher = NULL FROM branch
        WHERE c.comment_id = branch.comment_id RETURNING c.comment_id
    ) SELECT ARRAY(SELECT comment_id FROM removed)`, commentID, postID, viewer, owner).Scan(&deletedIDs)
	if err != nil {
		return err
	}
	if len(deletedIDs) == 0 {
		return ente.ErrPermissionDenied
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM space_comment_reactions WHERE comment_id = ANY($1)`, deletedIDs); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM space_notifications WHERE comment_id = ANY($1)`, deletedIDs); err != nil {
		return err
	}
	return tx.Commit()
}

func (r *CommentsRepository) React(ctx context.Context, viewer string, postID int64, commentID string, cipher []byte, targetActor string) (bool, error) {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return false, err
	}
	defer tx.Rollback()
	owner, err := discussionPostTx(ctx, tx, viewer, postID, true)
	if err != nil {
		return false, err
	}
	var author string
	if err := tx.QueryRowContext(ctx, `SELECT c.author_space_id FROM space_comments c
        WHERE c.comment_id = $1 AND c.post_id = $2 AND `+commentVisibleSQL, commentID, postID).Scan(&author); err != nil {
		return false, err
	}
	var notify bool
	if len(cipher) == 0 {
		if targetActor == "" {
			targetActor = viewer
		}
		if targetActor != viewer && viewer != owner {
			return false, ente.ErrPermissionDenied
		}
		if _, err := tx.ExecContext(ctx, `DELETE FROM space_comment_reactions WHERE comment_id = $1 AND actor_space_id = $2`, commentID, targetActor); err != nil {
			return false, err
		}
		if _, err := tx.ExecContext(ctx, `DELETE FROM space_notifications WHERE comment_id = $1 AND actor_space_id = $2 AND kind = 'comment_reaction'`, commentID, targetActor); err != nil {
			return false, err
		}
	} else {
		if _, err := tx.ExecContext(ctx, `INSERT INTO space_comment_reactions (comment_id, actor_space_id, cipher) VALUES ($1, $2, $3)
            ON CONFLICT (comment_id, actor_space_id) DO UPDATE SET cipher = EXCLUDED.cipher`, commentID, viewer, cipher); err != nil {
			return false, err
		}
		notify, err = commentNotificationTx(ctx, tx, owner, viewer, author, commentID, "comment_reaction")
		if err != nil {
			return false, err
		}
	}
	return notify, tx.Commit()
}

func (r *CommentsRepository) NotificationRecipients(ctx context.Context, actor string, postID int64, commentID string, reaction bool) ([]CommentNotificationRecipient, SpaceRecord, error) {
	var owner SpaceRecord
	rows, err := r.DB.QueryContext(ctx, `SELECT recipient.owner_id, n.kind, post_owner.owner_id, post_owner.space_id, post_owner.space_slug `+notificationSourcesSQL+`
        JOIN spaces recipient ON recipient.space_id = n.recipient_space_id
        JOIN spaces post_owner ON post_owner.space_id = p.space_id
        WHERE n.actor_space_id = $1 AND p.post_id = $2 AND n.comment_id = $3 AND (n.kind = 'comment_reaction') = $4 AND `+notificationVisibleSQL(commentVisibleSQL), actor, postID, commentID, reaction)
	if err != nil {
		return nil, owner, err
	}
	defer rows.Close()
	recipients := make([]CommentNotificationRecipient, 0)
	for rows.Next() {
		var recipient CommentNotificationRecipient
		if err := rows.Scan(&recipient.UserID, &recipient.Kind, &owner.OwnerID, &owner.SpaceID, &owner.SpaceSlug); err != nil {
			return nil, owner, err
		}
		recipients = append(recipients, recipient)
	}
	return recipients, owner, rows.Err()
}
