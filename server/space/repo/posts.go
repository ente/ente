package repo

import (
	"context"
	"database/sql"
	"errors"
	"strconv"
	"strings"

	"github.com/ente/museum/ente/base"
	"github.com/ente/stacktrace"
)

const MaxPostsPerSpace = 250

var ErrSpacePostLimitReached = errors.New("space post limit reached")

func postRecordSelectSQL(viewerLikedExpr string) string {
	return `
		SELECT p.post_id, p.space_id, w.space_slug, w.owner_id,
		       ` + spaceActorSelectColumns("w", "w_avatar", "author") + `,
		       p.encrypted_post_key, p.caption_cipher,
		       p.key_version, p.created_at,
		       ` + viewerLikedExpr + ` AS viewer_liked`
}

func scanPostRecords(rows *sql.Rows) ([]SpacePostRecord, error) {
	var out []SpacePostRecord
	for rows.Next() {
		rec, err := scanPostRecord(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *rec)
	}
	if err := rows.Err(); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return out, nil
}

func (r *PostsRepository) CreatePost(ctx context.Context, spaceID string, encryptedPostKey []byte, captionCipher []byte, keyVersion int, objects []SpacePostAssetRecord) (int64, int, error) {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return 0, 0, stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()
	var currentVersion int
	if err := tx.QueryRowContext(ctx, `
		SELECT current_version
		FROM spaces
		WHERE space_id = $1
		FOR UPDATE
	`, spaceID).Scan(&currentVersion); err != nil {
		return 0, 0, stacktrace.Propagate(err, "")
	}
	if currentVersion != keyVersion {
		return 0, 0, sql.ErrNoRows
	}
	var postCount int
	if err := tx.QueryRowContext(ctx, `
		SELECT COUNT(*)
		FROM space_posts
		WHERE space_id = $1 AND is_deleted = FALSE
	`, spaceID).Scan(&postCount); err != nil {
		return 0, 0, stacktrace.Propagate(err, "")
	}
	if postCount >= MaxPostsPerSpace {
		return 0, postCount, ErrSpacePostLimitReached
	}
	caption := []byte{}
	if captionCipher != nil {
		caption = captionCipher
	}
	var postID int64
	if err := tx.QueryRowContext(ctx, `
		INSERT INTO space_posts (space_id, encrypted_post_key, caption_cipher, key_version)
		VALUES ($1, $2, $3, $4)
		RETURNING post_id
	`, spaceID, encryptedPostKey, caption, keyVersion).Scan(&postID); err != nil {
		return 0, 0, stacktrace.Propagate(err, "")
	}
	for _, obj := range objects {
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO space_post_assets (post_id, object_key, bucket_id, size, position, metadata_cipher)
			VALUES ($1, $2, $3, $4, $5, $6)
		`, postID, obj.ObjectKey, obj.BucketID, obj.Size, obj.Position, obj.MetadataCipher); err != nil {
			return 0, 0, stacktrace.Propagate(err, "")
		}
		if err := ConsumeTempObjectTx(ctx, tx, obj.ObjectKey, TempObjectPurposePost, &spaceID); err != nil {
			return 0, 0, stacktrace.Propagate(err, "failed to consume staged space post upload")
		}
	}
	if err := tx.Commit(); err != nil {
		return 0, 0, stacktrace.Propagate(err, "")
	}
	return postID, postCount + 1, nil
}

func (r *PostsRepository) GetPost(ctx context.Context, postID int64, viewerSpaceID string) (*SpacePostRecord, error) {
	query := postRecordSelectSQL(`
		       EXISTS (
		           SELECT 1
		           FROM space_messages m
		           WHERE m.kind = 'post_like'
		             AND m.reply_post_id = p.post_id
		             AND m.sender_space_id = $2
		       )`) + `
			FROM space_posts p
			JOIN spaces w ON w.space_id = p.space_id
			` + spaceActorAvatarJoin("w", "w_avatar") + `
			WHERE p.post_id = $1 AND p.is_deleted = FALSE
		`
	return scanPostRecord(r.DB.QueryRowContext(ctx, query, postID, viewerSpaceID))
}

func (r *PostsRepository) ListPostsBySpace(ctx context.Context, spaceID string, viewerSpaceID string, cursor string, limit int) ([]SpacePostRecord, string, error) {
	limit = optionalInt(limit, 50)
	if limit > 100 {
		limit = 100
	}
	args := []any{spaceID, viewerSpaceID}
	query := postRecordSelectSQL(`
			       EXISTS (
			           SELECT 1
			           FROM space_messages m
			           WHERE m.kind = 'post_like'
			             AND m.reply_post_id = p.post_id
			             AND m.sender_space_id = $2
			       )`) + `
				FROM space_posts p
				JOIN spaces w ON w.space_id = p.space_id
				` + spaceActorAvatarJoin("w", "w_avatar") + `
				WHERE p.space_id = $1 AND p.is_deleted = FALSE`
	if cursorCreatedAt, cursorPostID, ok := parsePostCursor(cursor); ok {
		args = append(args, cursorCreatedAt, cursorPostID)
		query += ` AND (p.created_at, p.post_id) < ($3, $4)`
	}
	args = append(args, limit+1)
	query += ` ORDER BY p.created_at DESC, p.post_id DESC LIMIT $` + strconv.Itoa(len(args))
	rows, err := r.DB.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, "", stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	out, err := scanPostRecords(rows)
	if err != nil {
		return nil, "", err
	}
	nextCursor := ""
	if len(out) > limit {
		nextCursor = formatPostCursor(out[limit-1])
		out = out[:limit]
	}
	return out, nextCursor, nil
}

func (r *PostsRepository) ListFeed(ctx context.Context, viewerSpaceID string, cursor string, limit int) ([]SpacePostRecord, string, error) {
	limit = optionalInt(limit, 25)
	if limit > 100 {
		limit = 100
	}
	args := []any{viewerSpaceID}
	query := postRecordSelectSQL(`
			       CASE WHEN p.space_id = $1 THEN FALSE ELSE EXISTS (
			           SELECT 1
			           FROM space_messages m
			           WHERE m.kind = 'post_like'
			             AND m.reply_post_id = p.post_id
			             AND m.sender_space_id = $1
			       ) END`) + `
			FROM space_posts p
			JOIN spaces w ON w.space_id = p.space_id
			` + spaceActorAvatarJoin("w", "w_avatar") + `
			JOIN users u ON u.user_id = w.owner_id AND u.encrypted_email IS NOT NULL
			WHERE p.is_deleted = FALSE
			  AND (
			      p.space_id = $1 OR EXISTS (
			          SELECT 1 FROM space_friend_shares fs
			          WHERE fs.friend_space_id = $1 AND fs.space_id = p.space_id
			      )
			  )`
	if cursorCreatedAt, cursorPostID, ok := parsePostCursor(cursor); ok {
		args = append(args, cursorCreatedAt, cursorPostID)
		query += ` AND (p.created_at, p.post_id) < ($2, $3)`
	}
	args = append(args, limit+1)
	query += ` ORDER BY p.created_at DESC, p.post_id DESC LIMIT $` + strconv.Itoa(len(args))
	rows, err := r.DB.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, "", stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	out, err := scanPostRecords(rows)
	if err != nil {
		return nil, "", err
	}
	nextCursor := ""
	if len(out) > limit {
		nextCursor = formatPostCursor(out[limit-1])
		out = out[:limit]
	}
	return out, nextCursor, nil
}

func (r *PostsRepository) ListAssetsByPostIDs(ctx context.Context, postIDs []int64) (map[int64][]SpacePostAssetRecord, error) {
	if len(postIDs) == 0 {
		return map[int64][]SpacePostAssetRecord{}, nil
	}
	query, args := inClause("SELECT asset_id, post_id, object_key, bucket_id, size, position, metadata_cipher, created_at FROM space_post_assets WHERE post_id IN (%s) ORDER BY position ASC, asset_id ASC", postIDs, 0)
	rows, err := r.DB.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	result := make(map[int64][]SpacePostAssetRecord, len(postIDs))
	for rows.Next() {
		var rec SpacePostAssetRecord
		if err := rows.Scan(&rec.AssetID, &rec.PostID, &rec.ObjectKey, &rec.BucketID, &rec.Size, &rec.Position, &rec.MetadataCipher, &rec.CreatedAt); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		result[rec.PostID] = append(result[rec.PostID], rec)
	}
	return result, stacktrace.Propagate(rows.Err(), "")
}

func (r *PostsRepository) DeletePost(ctx context.Context, postID int64, spaceID string) error {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()
	res, err := tx.ExecContext(ctx, `
		UPDATE space_posts
		SET is_deleted = TRUE
		WHERE post_id = $1
		  AND space_id = $2
		  AND is_deleted = FALSE
	`, postID, spaceID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if affected == 0 {
		var isDeleted bool
		if err := tx.QueryRowContext(ctx, `
			SELECT is_deleted
			FROM space_posts
			WHERE post_id = $1 AND space_id = $2
		`, postID, spaceID).Scan(&isDeleted); err != nil {
			return stacktrace.Propagate(err, "")
		}
		if !isDeleted {
			return sql.ErrNoRows
		}
		if err := tx.Commit(); err != nil {
			return stacktrace.Propagate(err, "")
		}
		return nil
	}
	rows, err := tx.QueryContext(ctx, `
		SELECT a.object_key, a.bucket_id, COALESCE(a.size, 1), p.space_id
		FROM space_post_assets a
		JOIN space_posts p ON p.post_id = a.post_id
		WHERE a.post_id = $1
	`, postID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	var cleanupObjects []SpaceTempObjectRecord
	for rows.Next() {
		var rec SpaceTempObjectRecord
		if err := rows.Scan(&rec.ObjectKey, &rec.BucketID, &rec.ExpectedSize, &rec.SpaceID.String); err != nil {
			rows.Close()
			return stacktrace.Propagate(err, "")
		}
		rec.SpaceID.Valid = rec.SpaceID.String != ""
		rec.Purpose = TempObjectPurposePost
		cleanupObjects = append(cleanupObjects, rec)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return stacktrace.Propagate(err, "")
	}
	rows.Close()
	for _, object := range cleanupObjects {
		if err := QueueObjectCleanupTx(ctx, tx, object); err != nil {
			return err
		}
	}
	if err := tx.Commit(); err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}

func (r *PostsRepository) SetLikeWithCreated(ctx context.Context, postID int64, actorSpaceID string, like bool) (bool, error) {
	if like {
		res, err := r.DB.ExecContext(ctx, `
			INSERT INTO space_messages (
				message_id,
				sender_space_id,
				recipient_space_id,
				kind,
				reply_post_id
			)
			SELECT $3, $2, p.space_id, 'post_like', p.post_id
			FROM space_posts p
			WHERE p.post_id = $1
			  AND p.space_id <> $2
			  AND p.is_deleted = FALSE
			ON CONFLICT (reply_post_id, sender_space_id) WHERE kind = 'post_like' DO NOTHING
		`, postID, strings.TrimSpace(actorSpaceID), base.MustNewID("wmsg"))
		if err != nil {
			return false, stacktrace.Propagate(err, "")
		}
		affected, err := res.RowsAffected()
		if err != nil {
			return false, stacktrace.Propagate(err, "")
		}
		return affected > 0, nil
	}
	res, err := r.DB.ExecContext(ctx, `DELETE FROM space_messages WHERE kind = 'post_like' AND reply_post_id = $1 AND sender_space_id = $2`, postID, strings.TrimSpace(actorSpaceID))
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	return affected > 0, nil
}

func (r *PostsRepository) UpdateCaption(ctx context.Context, postID int64, spaceID string, captionCipher []byte) error {
	caption := []byte{}
	if captionCipher != nil {
		caption = captionCipher
	}
	res, err := r.DB.ExecContext(ctx, `
		UPDATE space_posts
		SET caption_cipher = $1
		WHERE post_id = $2
		  AND space_id = $3
		  AND is_deleted = FALSE
	`, caption, postID, spaceID)
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

func scanPostRecord(scanner interface{ Scan(dest ...any) error }) (*SpacePostRecord, error) {
	var rec SpacePostRecord
	dest := []any{&rec.PostID, &rec.SpaceID, &rec.SpaceSlug, &rec.OwnerID}
	dest = append(dest, spaceActorScanDest(&rec.Author)...)
	dest = append(dest, &rec.EncryptedPostKey, &rec.CaptionCipher, &rec.KeyVersion, &rec.CreatedAt, &rec.ViewerLiked)
	if err := scanner.Scan(dest...); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &rec, nil
}

func parsePostCursor(cursor string) (int64, int64, bool) {
	createdAtText, postIDText, ok := strings.Cut(strings.TrimSpace(cursor), ":")
	if !ok {
		return 0, 0, false
	}
	createdAt, err := strconv.ParseInt(createdAtText, 10, 64)
	if err != nil || createdAt <= 0 {
		return 0, 0, false
	}
	postID, err := strconv.ParseInt(postIDText, 10, 64)
	if err != nil || postID <= 0 {
		return 0, 0, false
	}
	return createdAt, postID, true
}

func formatPostCursor(post SpacePostRecord) string {
	return strconv.FormatInt(post.CreatedAt, 10) + ":" + strconv.FormatInt(post.PostID, 10)
}

func inClause(format string, ids []int64, offset int) (string, []any) {
	parts := make([]string, len(ids))
	args := make([]any, 0, len(ids))
	for i, id := range ids {
		parts[i] = "$" + strconv.Itoa(offset+i+1)
		args = append(args, id)
	}
	return strings.Replace(format, "%s", strings.Join(parts, ","), 1), args
}
