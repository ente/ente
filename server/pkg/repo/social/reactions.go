package social

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/ente/museum/ente"
	socialentity "github.com/ente/museum/ente/social"
	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

// ReactionsRepository manages reaction records.
type ReactionsRepository struct {
	DB *sql.DB
}

func (repo *ReactionsRepository) Upsert(ctx context.Context, reaction socialentity.Reaction) (string, error) {
	var id string
	err := repo.DB.QueryRowContext(ctx, `
        INSERT INTO reactions (id, collection_id, file_id, comment_id, user_id, anon_user_id, cipher, nonce, is_deleted)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, FALSE)
        ON CONFLICT (actor_key, unique_key)
        DO UPDATE SET cipher = EXCLUDED.cipher,
                      nonce = EXCLUDED.nonce,
                      is_deleted = FALSE,
                      updated_at = now_utc_micro_seconds()
        RETURNING id
    `,
		reaction.ID,
		reaction.CollectionID,
		reaction.FileID,
		reaction.CommentID,
		reaction.UserID,
		reaction.AnonUserID,
		reaction.Cipher,
		reaction.Nonce,
	).Scan(&id)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	return id, nil
}

func (repo *ReactionsRepository) SoftDeleteByID(ctx context.Context, id string, userID int64, anonUserID *string) error {
	actorKey, err := buildActorKey(userID, anonUserID)
	if err != nil {
		return err
	}
	result, err := repo.DB.ExecContext(ctx, `
        UPDATE reactions
        SET is_deleted = TRUE,
            cipher = NULL,
            nonce = NULL,
            updated_at = now_utc_micro_seconds()
        WHERE id = $1
          AND actor_key = $2
    `, id, actorKey)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if rows == 0 {
		return stacktrace.Propagate(ente.ErrNotFound, "")
	}
	return nil
}

// SoftDeleteByCollectionAndUser removes all reactions created by a user inside a collection.
func (repo *ReactionsRepository) SoftDeleteByCollectionAndUser(ctx context.Context, collectionID int64, userID int64) error {
	_, err := repo.DB.ExecContext(ctx, `
        UPDATE reactions
        SET is_deleted = TRUE,
            cipher = NULL,
            nonce = NULL,
            updated_at = now_utc_micro_seconds()
        WHERE collection_id = $1
          AND user_id = $2
          AND is_deleted = FALSE
    `, collectionID, userID)
	return stacktrace.Propagate(err, "")
}

func (repo *ReactionsRepository) GetByID(ctx context.Context, id string) (*socialentity.Reaction, error) {
	var (
		file    sql.NullInt64
		comment sql.NullString
		anon    sql.NullString
		cipher  sql.NullString
		nonce   sql.NullString
	)
	reaction := &socialentity.Reaction{}
	err := repo.DB.QueryRowContext(ctx, `
        SELECT id, collection_id, file_id, comment_id, user_id, anon_user_id, cipher, nonce, is_deleted, created_at, updated_at
        FROM reactions
        WHERE id = $1
    `, id).Scan(
		&reaction.ID,
		&reaction.CollectionID,
		&file,
		&comment,
		&reaction.UserID,
		&anon,
		&cipher,
		&nonce,
		&reaction.IsDeleted,
		&reaction.CreatedAt,
		&reaction.UpdatedAt,
	)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if file.Valid {
		reaction.FileID = &file.Int64
	}
	if comment.Valid {
		reaction.CommentID = &comment.String
	}
	if anon.Valid {
		reaction.AnonUserID = &anon.String
	}
	if cipher.Valid {
		reaction.Cipher = cipher.String
	}
	if nonce.Valid {
		reaction.Nonce = nonce.String
	}
	return reaction, nil
}

func (repo *ReactionsRepository) GetDiff(ctx context.Context, collectionID int64, since int64, limit int, fileID *int64, commentID *string) ([]socialentity.Reaction, bool, error) {
	query := `
        SELECT id, collection_id, file_id, comment_id, user_id, anon_user_id, cipher, nonce, is_deleted, created_at, updated_at
        FROM reactions
        WHERE collection_id = $1
          AND updated_at > $2
          AND (
              $3::bigint IS NULL
              OR file_id = $3::bigint
              OR comment_id IN (SELECT id FROM comments WHERE collection_id = $1 AND file_id = $3::bigint)
          )
          AND ($4::text IS NULL OR comment_id = $4::text)
        ORDER BY updated_at ASC
        LIMIT $5
    `
	rows, err := repo.DB.QueryContext(ctx, query, collectionID, since, fileID, commentID, limit+1)
	if err != nil {
		return nil, false, stacktrace.Propagate(err, "")
	}
	defer rows.Close()

	reactions := make([]socialentity.Reaction, 0, limit+1)
	for rows.Next() {
		var (
			file     sql.NullInt64
			comment  sql.NullString
			anon     sql.NullString
			cipher   sql.NullString
			nonce    sql.NullString
			reaction socialentity.Reaction
		)
		if err := rows.Scan(
			&reaction.ID,
			&reaction.CollectionID,
			&file,
			&comment,
			&reaction.UserID,
			&anon,
			&cipher,
			&nonce,
			&reaction.IsDeleted,
			&reaction.CreatedAt,
			&reaction.UpdatedAt,
		); err != nil {
			return nil, false, stacktrace.Propagate(err, "")
		}
		if file.Valid {
			reaction.FileID = &file.Int64
		}
		if comment.Valid {
			reaction.CommentID = &comment.String
		}
		if anon.Valid {
			reaction.AnonUserID = &anon.String
		}
		if cipher.Valid {
			reaction.Cipher = cipher.String
		}
		if nonce.Valid {
			reaction.Nonce = nonce.String
		}
		reactions = append(reactions, reaction)
	}
	if err := rows.Err(); err != nil {
		return nil, false, stacktrace.Propagate(err, "")
	}

	hasMore := false
	if len(reactions) > limit {
		hasMore = true
		reactions = reactions[:limit]
	}
	return reactions, hasMore, nil
}

func (repo *ReactionsRepository) CountActiveByCollection(ctx context.Context, collectionIDs []int64) (map[int64]int64, error) {
	counts := make(map[int64]int64)
	if len(collectionIDs) == 0 {
		return counts, nil
	}
	rows, err := repo.DB.QueryContext(ctx, `
        SELECT collection_id, COUNT(*)
        FROM reactions
        WHERE collection_id = ANY($1)
          AND is_deleted = FALSE
        GROUP BY collection_id
    `, pq.Array(collectionIDs))
	if err != nil {
		return counts, stacktrace.Propagate(err, "")
	}
	defer rows.Close()

	for rows.Next() {
		var collectionID int64
		var count int64
		if err := rows.Scan(&collectionID, &count); err != nil {
			return counts, stacktrace.Propagate(err, "")
		}
		counts[collectionID] = count
	}
	if err := rows.Err(); err != nil {
		return counts, stacktrace.Propagate(err, "")
	}
	return counts, nil
}

// LatestUpdateByCollection returns the most recent updated_at timestamp for each collection.
func (repo *ReactionsRepository) LatestUpdateByCollection(ctx context.Context, collectionIDs []int64) (map[int64]int64, error) {
	results := make(map[int64]int64)
	if len(collectionIDs) == 0 {
		return results, nil
	}
	rows, err := repo.DB.QueryContext(ctx, `
        SELECT collection_id, MAX(updated_at)
        FROM reactions
        WHERE collection_id = ANY($1)
        GROUP BY collection_id
    `, pq.Array(collectionIDs))
	if err != nil {
		return results, stacktrace.Propagate(err, "")
	}
	defer rows.Close()

	for rows.Next() {
		var (
			collectionID int64
			updatedAt    int64
		)
		if err := rows.Scan(&collectionID, &updatedAt); err != nil {
			return results, stacktrace.Propagate(err, "")
		}
		results[collectionID] = updatedAt
	}
	if err := rows.Err(); err != nil {
		return results, stacktrace.Propagate(err, "")
	}
	return results, nil
}

func (repo *ReactionsRepository) GetActiveUserIDs(ctx context.Context, collectionID int64) ([]int64, error) {
	rows, err := repo.DB.QueryContext(ctx, `
        SELECT DISTINCT user_id
        FROM reactions
        WHERE collection_id = $1
          AND user_id > 0
          AND is_deleted = FALSE
    `, collectionID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	ids := make([]int64, 0)
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return ids, nil
}

func buildActorKey(userID int64, anonUserID *string) (string, error) {
	if userID == -1 {
		if anonUserID == nil || *anonUserID == "" {
			return "", stacktrace.Propagate(ente.ErrBadRequest, "missing anon user id for anonymous actor")
		}
		return fmt.Sprintf("A:%s", *anonUserID), nil
	}
	if anonUserID != nil {
		return "", stacktrace.Propagate(ente.ErrBadRequest, "anon_user_id must be empty for authenticated actor")
	}
	return fmt.Sprintf("U:%d", userID), nil
}
