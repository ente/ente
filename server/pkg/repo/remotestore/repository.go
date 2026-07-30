package remotestore

import (
	"context"
	"database/sql"
	"errors"

	"github.com/ente/museum/ente"
	"github.com/lib/pq"

	"github.com/ente/stacktrace"
)

// Repository defines the methods for inserting, updating and retrieving
// remote store key and values
type Repository struct {
	DB *sql.DB
}

func (r *Repository) InsertOrUpdate(ctx context.Context, userID int64, key string, value string) error {
	_, err := r.DB.ExecContext(ctx, `INSERT INTO remote_store(user_id, key_name, key_value) VALUES ($1,$2,$3)
						 ON CONFLICT (user_id, key_name) DO UPDATE SET key_value = $3;
						 `,
		userID, //$1 user_id
		key,    // $2 key_name
		value,  // $3 key_value
	)

	if err != nil {
		// Check for unique violation (PostgreSQL error code 23505)
		var pgErr *pq.Error
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			if pgErr.Constraint == "remote_store_custom_domain_unique_idx" {
				return ente.NewConflictError("custom domain already exists for another user")
			}
		}
		return stacktrace.Propagate(err, "failed to insert/update")
	}
	return stacktrace.Propagate(err, "failed to insert/update")
}

func (r *Repository) RemoveKey(ctx context.Context, userID int64, key string) error {
	_, err := r.DB.ExecContext(ctx, `DELETE FROM remote_store
		WHERE user_id = $1 AND key_name = $2`,
		userID, // $1
		key,    // $2
	)
	return stacktrace.Propagate(err, "failed to remove key")
}

func (r *Repository) DomainOwner(ctx context.Context, domain string) (*int64, error) {
	// Check if the domain is already taken by another user
	rows := r.DB.QueryRowContext(ctx, `SELECT user_id FROM remote_store
	   WHERE key_name = $1 AND key_value = $2`,
		ente.CustomDomain, // $1
		domain,            // $2
	)
	var userID int64
	err := rows.Scan(&userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, stacktrace.Propagate(&ente.ErrNotFoundError, "")
		}
		return nil, stacktrace.Propagate(err, "failed to fetch domain owner")
	}
	return &userID, nil
}

func (r *Repository) GetDomain(ctx context.Context, userID int64) (*string, error) {
	// Fetch the custom domain for the user
	rows := r.DB.QueryRowContext(ctx, `SELECT key_value FROM remote_store
	   WHERE user_id = $1 AND key_name = $2`,
		userID,            // $1
		ente.CustomDomain, // $2
	)
	var domain string
	err := rows.Scan(&domain)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, stacktrace.Propagate(err, "failed to fetch custom domain")
	}
	return &domain, nil

}

// GetEffectiveDomain returns the resolved custom domain for the user (family pointers resolved).
func (r *Repository) GetEffectiveDomain(ctx context.Context, userID int64) (*string, error) {
	domain, err := r.GetDomain(ctx, userID)
	if err != nil || domain == nil || *domain == "" {
		return domain, err
	}
	resolved, resolveErr := ente.ResolveCustomDomainValue(*domain)
	if resolveErr != nil {
		return nil, stacktrace.Propagate(resolveErr, "failed to resolve custom domain")
	}
	return &resolved, nil
}

// GetValue fetches and return the value for given user_id and key
func (r *Repository) GetValue(ctx context.Context, userID int64, key string) (string, error) {
	rows := r.DB.QueryRowContext(ctx, `SELECT key_value FROM remote_store
	   WHERE user_id = $1
	   and key_name = $2`,
		userID, // $1
		key,    // %2
	)
	var keyValue string
	err := rows.Scan(&keyValue)
	if err != nil {
		return keyValue, stacktrace.Propagate(err, "reading value failed")
	}
	return keyValue, nil
}

// GetAllValues fetches and return all the key value pairs for given user_id
func (r *Repository) GetAllValues(ctx context.Context, userID int64) (map[string]string, error) {
	rows, err := r.DB.QueryContext(ctx, `SELECT key_name, key_value FROM remote_store
	   WHERE user_id = $1`,
		userID, // $1
	)
	if err != nil {
		return nil, stacktrace.Propagate(err, "reading value failed")
	}
	defer rows.Close()
	values := make(map[string]string)
	for rows.Next() {
		var key, value string
		err := rows.Scan(&key, &value)
		if err != nil {
			return nil, stacktrace.Propagate(err, "reading value failed")
		}
		values[key] = value
	}
	return values, nil
}
