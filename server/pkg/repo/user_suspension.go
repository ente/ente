package repo

import (
	"context"

	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
)

func (repo *UserAuthRepository) SetUserSuspended(ctx context.Context, userID int64, suspended bool) ([]RevokedToken, error) {
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()

	var active bool
	if err = tx.QueryRowContext(ctx, `SELECT encrypted_email IS NOT NULL FROM users WHERE user_id = $1 FOR NO KEY UPDATE`, userID).Scan(&active); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if !active {
		return nil, ente.ErrUserDeleted
	}
	if _, err = tx.ExecContext(ctx, `UPDATE users SET is_suspended = $2 WHERE user_id = $1`, userID, suspended); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}

	var tokens []RevokedToken
	if suspended {
		tokens, err = markTokensDeleted(tx, `UPDATE tokens SET is_deleted = true WHERE user_id = $1 AND is_deleted = false RETURNING app, token_hash`, userID)
		if err != nil {
			return nil, err
		}
		if _, err = tx.ExecContext(ctx, `
			WITH deleted_push_tokens AS (
				DELETE FROM push_tokens WHERE user_id = $1
			), deleted_space_sessions AS (
				DELETE FROM space_browser_sessions WHERE user_id = $1
			)
			UPDATE casting SET is_deleted = true WHERE cast_user = $1 AND is_deleted = false`, userID); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
	}
	if err = tx.Commit(); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return tokens, nil
}
