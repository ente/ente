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

const (
	MaxPostsPerSpace = 250
	MaxPostObjects   = 10
)

var ErrSpacePostLimitReached = errors.New("space post limit reached")

func (r *PostsRepository) CountPosts(ctx context.Context, spaceID string) (int64, error) {
	var count int64
	if err := r.DB.QueryRowContext(ctx, `
		SELECT COUNT(*)
		FROM space_posts
		WHERE space_id = $1 AND is_deleted = FALSE
	`, spaceID).Scan(&count); err != nil {
		return 0, stacktrace.Propagate(err, "")
	}
	return count, nil
}

func (r *PostsRepository) LatestPostCreatedAt(ctx context.Context, spaceID string) (int64, error) {
	var createdAt sql.NullInt64
	if err := r.DB.QueryRowContext(ctx, `
		SELECT MAX(created_at)
		FROM space_posts
		WHERE space_id = $1 AND is_deleted = FALSE
	`, spaceID).Scan(&createdAt); err != nil {
		return 0, stacktrace.Propagate(err, "")
	}
	return createdAt.Int64, nil
}

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

func (r *PostsRepository) PostIDForRequest(ctx context.Context, spaceID, requestID string) (int64, error) {
	var postID int64
	err := r.DB.QueryRowContext(ctx, "SELECT post_id FROM space_posts WHERE space_id = $1 AND client_request_id = $2", spaceID, requestID).Scan(&postID)
	return postID, err
}

func (r *PostsRepository) CreatePost(ctx context.Context, spaceID string, encryptedPostKey []byte, captionCipher []byte, keyVersion int, objects []SpacePostAssetRecord, clientRequestID string) (int64, int, error) {
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
	if clientRequestID != "" {
		var existingID int64
		err := tx.QueryRowContext(ctx, "SELECT post_id FROM space_posts WHERE space_id = $1 AND client_request_id = $2", spaceID, clientRequestID).Scan(&existingID)
		if err == nil {
			return existingID, 0, nil
		}
		if err != sql.ErrNoRows {
			return 0, 0, err
		}
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
		INSERT INTO space_posts (space_id, encrypted_post_key, caption_cipher, key_version, client_request_id)
		VALUES ($1, $2, $3, $4, NULLIF($5, ''))
		RETURNING post_id
	`, spaceID, encryptedPostKey, caption, keyVersion, clientRequestID).Scan(&postID); err != nil {
		return 0, 0, stacktrace.Propagate(err, "")
	}
	for _, obj := range objects {
		role := obj.Role
		if role == "" {
			role = "preview"
		}
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO space_post_assets (post_id, object_key, bucket_id, size, position, metadata_cipher, role)
			VALUES ($1, $2, $3, $4, $5, $6, $7)
		`, postID, obj.ObjectKey, obj.BucketID, obj.Size, obj.Position, obj.MetadataCipher, role); err != nil {
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
		           FROM space_post_likes l
		           WHERE l.post_id = p.post_id
		             AND l.actor_space_id = $2
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
	if limit > MaxPostsPerSpace {
		limit = MaxPostsPerSpace
	}
	args := []any{spaceID, viewerSpaceID}
	query := postRecordSelectSQL(`
			       EXISTS (
			           SELECT 1
			           FROM space_post_likes l
			           WHERE l.post_id = p.post_id
			             AND l.actor_space_id = $2
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
			           FROM space_post_likes l
			           WHERE l.post_id = p.post_id
			             AND l.actor_space_id = $1
			       ) END`) + `
			FROM (
			    SELECT $1::TEXT AS space_id
			    UNION ALL
			    SELECT space_id FROM space_friend_shares WHERE friend_space_id = $1
			) accessible_spaces
			JOIN space_posts p ON p.space_id = accessible_spaces.space_id
			JOIN spaces w ON w.space_id = p.space_id
			` + spaceActorAvatarJoin("w", "w_avatar") + `
			JOIN users u ON u.user_id = w.owner_id AND u.encrypted_email IS NOT NULL
			WHERE p.is_deleted = FALSE`
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
	query, args := inClause("SELECT asset_id, post_id, object_key, bucket_id, size, position, metadata_cipher, created_at, role FROM space_post_assets WHERE post_id IN (%s) ORDER BY position ASC, asset_id ASC", postIDs, 0)
	rows, err := r.DB.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	result := make(map[int64][]SpacePostAssetRecord, len(postIDs))
	for rows.Next() {
		var rec SpacePostAssetRecord
		if err := rows.Scan(&rec.AssetID, &rec.PostID, &rec.ObjectKey, &rec.BucketID, &rec.Size, &rec.Position, &rec.MetadataCipher, &rec.CreatedAt, &rec.Role); err != nil {
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
	if _, err := tx.ExecContext(ctx, `DELETE FROM space_post_likes WHERE post_id = $1`, postID); err != nil {
		return stacktrace.Propagate(err, "")
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
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()
	var recipientSpaceID string
	if err := tx.QueryRowContext(ctx, `
		SELECT space_id FROM space_posts
		WHERE post_id = $1 AND space_id <> $2 AND is_deleted = FALSE
		FOR UPDATE
	`, postID, actorSpaceID).Scan(&recipientSpaceID); err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	if !like {
		result, err := tx.ExecContext(ctx, `DELETE FROM space_post_likes WHERE post_id = $1 AND actor_space_id = $2`, postID, actorSpaceID)
		if err != nil {
			return false, stacktrace.Propagate(err, "")
		}
		changed, err := result.RowsAffected()
		if err != nil {
			return false, stacktrace.Propagate(err, "")
		}
		return changed > 0, stacktrace.Propagate(tx.Commit(), "")
	}
	likeID := base.MustNewID("wlike")
	var createdAt int64
	err = tx.QueryRowContext(ctx, `
		INSERT INTO space_post_likes (like_id, post_id, actor_space_id)
		VALUES ($1, $2, $3)
		ON CONFLICT (post_id, actor_space_id) DO NOTHING
		RETURNING created_at
	`, likeID, postID, actorSpaceID).Scan(&createdAt)
	if err == sql.ErrNoRows {
		return false, stacktrace.Propagate(tx.Commit(), "")
	}
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO space_notifications (notification_id, recipient_space_id, actor_space_id, kind, post_like_id, created_at)
		VALUES ($1, $2, $3, 'post_like', $4, $5)
	`, base.MustNewID("wnot"), recipientSpaceID, actorSpaceID, likeID, createdAt); err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	return true, stacktrace.Propagate(tx.Commit(), "")
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
