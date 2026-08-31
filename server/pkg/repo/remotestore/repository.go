package remotestore

import (
	"context"
	"database/sql"
	"errors"

	"github.com/ente/museum/ente"
	"github.com/lib/pq"

	"github.com/ente/stacktrace"
)

type Repository struct {
	DB *sql.DB
}

func (r *Repository) InsertOrUpdate(ctx context.Context, userID int64, key string, value string) error {
	return r.insertOrUpdate(ctx, userID, key, value, nil)
}

func (r *Repository) InsertOrUpdateCustomDomain(ctx context.Context, userID int64, value string) error {
	canonicalDomain, err := ente.CanonicalDomain(value)
	if err != nil {
		return stacktrace.Propagate(err, "failed to canonicalize custom domain")
	}
	return r.insertOrUpdate(ctx, userID, string(ente.CustomDomain), value, &canonicalDomain)
}

func (r *Repository) insertOrUpdate(ctx context.Context, userID int64, key string, value string, canonicalValue *string) error {
	_, err := r.DB.ExecContext(ctx, `INSERT INTO remote_store(user_id, key_name, key_value, canonical_value) VALUES ($1,$2,$3,$4)
						 ON CONFLICT (user_id, key_name) DO UPDATE SET key_value = $3, canonical_value = $4;
						 `,
		userID,
		key,
		value,
		canonicalValue,
	)

	if err != nil {
		var pgErr *pq.Error
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			if pgErr.Constraint == "remote_store_custom_domain_unique_idx" || pgErr.Constraint == "remote_store_custom_domain_canonical_unique_idx" {
				return ente.NewConflictError("custom domain already exists for another user")
			}
		}
		return stacktrace.Propagate(err, "failed to insert/update")
	}
	return nil
}

func (r *Repository) RemoveKey(ctx context.Context, userID int64, key string) error {
	_, err := r.DB.ExecContext(ctx, `DELETE FROM remote_store
		WHERE user_id = $1 AND key_name = $2`,
		userID,
		key,
	)
	return stacktrace.Propagate(err, "failed to remove key")
}

func (r *Repository) DomainOwner(ctx context.Context, domain string) (*int64, error) {
	canonicalDomain, err := ente.CanonicalDomain(domain)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to canonicalize custom domain")
	}
	row := r.DB.QueryRowContext(ctx, `SELECT user_id FROM remote_store
	   WHERE key_name = $1 AND canonical_value = $2`,
		ente.CustomDomain,
		canonicalDomain,
	)
	var userID int64
	err = row.Scan(&userID)
	if errors.Is(err, sql.ErrNoRows) {
		err = r.DB.QueryRowContext(ctx, `SELECT user_id FROM remote_store
			WHERE key_name = $1 AND lower(key_value) = lower($2)`, ente.CustomDomain, domain).Scan(&userID)
	}
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, stacktrace.Propagate(&ente.ErrNotFoundError, "")
		}
		return nil, stacktrace.Propagate(err, "failed to fetch domain owner")
	}
	return &userID, nil
}

func (r *Repository) GetDomain(ctx context.Context, userID int64) (*string, error) {
	rows := r.DB.QueryRowContext(ctx, `SELECT key_value FROM remote_store
	   WHERE user_id = $1 AND key_name = $2`,
		userID,
		ente.CustomDomain,
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

func (r *Repository) GetValue(ctx context.Context, userID int64, key string) (string, error) {
	rows := r.DB.QueryRowContext(ctx, `SELECT key_value FROM remote_store
	   WHERE user_id = $1
	   and key_name = $2`,
		userID,
		key,
	)
	var keyValue string
	err := rows.Scan(&keyValue)
	if err != nil {
		return keyValue, stacktrace.Propagate(err, "reading value failed")
	}
	return keyValue, nil
}

func (r *Repository) GetAllValues(ctx context.Context, userID int64) (map[string]string, error) {
	rows, err := r.DB.QueryContext(ctx, `SELECT key_name, key_value FROM remote_store
	   WHERE user_id = $1`,
		userID,
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
