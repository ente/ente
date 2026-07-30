package social

import (
	"context"
	"database/sql"

	socialentity "github.com/ente/museum/ente/social"
	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

// AnonUsersRepository manages anonymous user profiles tied to public collections.
type AnonUsersRepository struct {
	DB *sql.DB
}

func (r *AnonUsersRepository) Insert(ctx context.Context, user socialentity.AnonUser) error {
	_, err := r.DB.ExecContext(ctx, `
        INSERT INTO anon_users (id, collection_id, cipher, nonce)
        VALUES ($1, $2, $3, $4)
    `,
		user.ID,
		user.CollectionID,
		user.Cipher,
		user.Nonce,
	)
	return stacktrace.Propagate(err, "")
}

func (r *AnonUsersRepository) GetByID(ctx context.Context, id string) (*socialentity.AnonUser, error) {
	anon := &socialentity.AnonUser{}
	err := r.DB.QueryRowContext(ctx, `
        SELECT id, collection_id, cipher, nonce, created_at, updated_at
        FROM anon_users
        WHERE id = $1
    `, id).Scan(
		&anon.ID,
		&anon.CollectionID,
		&anon.Cipher,
		&anon.Nonce,
		&anon.CreatedAt,
		&anon.UpdatedAt,
	)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return anon, nil
}

func (r *AnonUsersRepository) ListByCollection(ctx context.Context, collectionID int64) ([]socialentity.AnonUser, error) {
	rows, err := r.DB.QueryContext(ctx, `
        SELECT id, collection_id, cipher, nonce, created_at, updated_at
        FROM anon_users
        WHERE collection_id = $1
        ORDER BY created_at ASC
    `, collectionID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()

	var result []socialentity.AnonUser
	for rows.Next() {
		var anon socialentity.AnonUser
		if err := rows.Scan(
			&anon.ID,
			&anon.CollectionID,
			&anon.Cipher,
			&anon.Nonce,
			&anon.CreatedAt,
			&anon.UpdatedAt,
		); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		result = append(result, anon)
	}
	if err := rows.Err(); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return result, nil
}

// LatestUpdateByCollection returns the most recent updated_at timestamp per collection.
func (r *AnonUsersRepository) LatestUpdateByCollection(ctx context.Context, collectionIDs []int64) (map[int64]int64, error) {
	results := make(map[int64]int64)
	if len(collectionIDs) == 0 {
		return results, nil
	}
	rows, err := r.DB.QueryContext(ctx, `
        SELECT collection_id, MAX(updated_at)
        FROM anon_users
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
