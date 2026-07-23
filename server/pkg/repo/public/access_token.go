package public

import (
	"context"
	"database/sql"

	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
)

func ensureAccessTokenAvailable(ctx context.Context, tx *sql.Tx, token string) error {
	var exists bool

	err := tx.QueryRowContext(
		ctx,
		`SELECT EXISTS(
			SELECT 1 FROM public_file_tokens WHERE access_token = $1 AND is_disabled = FALSE
		)`,
		token,
	).Scan(&exists)
	if err != nil {
		return stacktrace.Propagate(err, "failed to check existing file access tokens")
	}
	if exists {
		return ente.ErrAccessTokenInUse
	}

	err = tx.QueryRowContext(
		ctx,
		`SELECT EXISTS(
			SELECT 1 FROM public_collection_tokens WHERE access_token = $1 AND is_disabled = FALSE
		)`,
		token,
	).Scan(&exists)
	if err != nil {
		return stacktrace.Propagate(err, "failed to check existing collection access tokens")
	}
	if exists {
		return ente.ErrAccessTokenInUse
	}
	return nil
}
