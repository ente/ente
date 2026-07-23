package authenticator

import (
	"context"
	"database/sql"
	"errors"

	"github.com/ente/museum/ente"
	model "github.com/ente/museum/ente/authenticator"
	"github.com/ente/stacktrace"
)

// CreateTotpEntry inserts a new &{totp.CreateTotpEntry} entry
func (r *Repository) CreateKey(ctx context.Context, userID int64, entry model.CreateKeyRequest) error {
	_, err := r.DB.ExecContext(ctx, `INSERT into authenticator_key(
                         user_id,
                         encrypted_key,
                         header) VALUES ($1,$2,$3)`,
		userID,             // $1 user_id
		entry.EncryptedKey, // $2 encrypted_data
		entry.Header)

	if err != nil {
		if err.Error() == "pq: duplicate key value violates unique constraint \"authenticator_key_pkey\"" {
			return ente.NewConflictError("Key already exists")
		}
		return stacktrace.Propagate(err, "Failed to createTotpEntry")
	}
	return nil
}

func (r *Repository) GetKey(ctx context.Context, userID int64) (model.Key, error) {
	row := r.DB.QueryRowContext(ctx, `SELECT user_id, encrypted_key, header,
	 created_at from authenticator_key where user_id = $1`, userID)
	var result model.Key
	err := row.Scan(&result.UserID, &result.EncryptedKey, &result.Header, &result.CreatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return result, stacktrace.Propagate(&ente.ErrNotFoundError, "authKey is not present")
		}
		return result, stacktrace.Propagate(err, "failed to authKey")
	}
	return result, nil
}
