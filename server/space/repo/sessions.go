package repo

import (
	"context"

	"github.com/ente/museum/ente"
	timeutil "github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
)

func (r *SessionsRepository) ExchangeBrowserSession(ctx context.Context, authToken string, tokenHash []byte, userID int64, sessionWrapKey string, expiresAt int64) error {
	result, err := r.DB.ExecContext(ctx, `
		WITH consumed_token AS (
			UPDATE tokens
			SET is_deleted = TRUE
			WHERE user_id = $1
			  AND token = $2
			  AND is_deleted = FALSE
			  AND (last_used_at IS NULL OR last_used_at >= now_utc_micro_seconds() - (365::BIGINT * 24 * 60 * 60 * 1000 * 1000))
			RETURNING user_id
		)
		INSERT INTO space_browser_sessions (token_hash, user_id, session_wrap_key, expires_at)
		SELECT $3, user_id, $4, $5
		FROM consumed_token
	`, userID, authToken, tokenHash, sessionWrapKey, expiresAt)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	created, err := result.RowsAffected()
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if created == 0 {
		return ente.ErrAuthenticationRequired
	}
	return nil
}

func (r *SessionsRepository) CreateBrowserSession(ctx context.Context, tokenHash []byte, userID int64, sessionWrapKey string, expiresAt int64) error {
	_, err := r.DB.ExecContext(ctx, `
		INSERT INTO space_browser_sessions (token_hash, user_id, session_wrap_key, expires_at)
		VALUES ($1, $2, $3, $4)
	`, tokenHash, userID, sessionWrapKey, expiresAt)
	return stacktrace.Propagate(err, "")
}

func (r *SessionsRepository) GetBrowserSession(ctx context.Context, tokenHash []byte) (*SpaceBrowserSessionRecord, error) {
	row := r.DB.QueryRowContext(ctx, `
		SELECT s.token_hash, s.user_id, s.session_wrap_key, s.expires_at, s.created_at, s.updated_at, s.last_used_at
		FROM space_browser_sessions s
		JOIN users u ON u.user_id = s.user_id AND u.encrypted_email IS NOT NULL
		WHERE s.token_hash = $1
	`, tokenHash)
	rec := &SpaceBrowserSessionRecord{}
	err := row.Scan(
		&rec.TokenHash,
		&rec.UserID,
		&rec.SessionWrapKey,
		&rec.ExpiresAt,
		&rec.CreatedAt,
		&rec.UpdatedAt,
		&rec.LastUsedAt,
	)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return rec, nil
}

func (r *SessionsRepository) TouchBrowserSession(ctx context.Context, tokenHash []byte, lastUsedBefore int64) error {
	_, err := r.DB.ExecContext(ctx, `
		UPDATE space_browser_sessions
		SET last_used_at = $1
		WHERE token_hash = $2 AND last_used_at <= $3
	`, timeutil.Microseconds(), tokenHash, lastUsedBefore)
	return stacktrace.Propagate(err, "")
}

func (r *SessionsRepository) DeleteBrowserSession(ctx context.Context, tokenHash []byte) error {
	_, err := r.DB.ExecContext(ctx, `DELETE FROM space_browser_sessions WHERE token_hash = $1`, tokenHash)
	return stacktrace.Propagate(err, "")
}

func (r *SessionsRepository) DeleteBrowserSessionsForToken(ctx context.Context, tokenHash []byte) error {
	result, err := r.DB.ExecContext(ctx, `
		DELETE FROM space_browser_sessions
		WHERE user_id = (
			SELECT user_id
			FROM space_browser_sessions
			WHERE token_hash = $1 AND expires_at > now_utc_micro_seconds()
		)
	`, tokenHash)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	deleted, err := result.RowsAffected()
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if deleted == 0 {
		return ente.ErrAuthenticationRequired
	}
	return nil
}

func (r *SessionsRepository) DeleteBrowserSessionsForUser(ctx context.Context, userID int64) error {
	_, err := r.DB.ExecContext(ctx, `DELETE FROM space_browser_sessions WHERE user_id = $1`, userID)
	return stacktrace.Propagate(err, "")
}

func (m *Module) RevokeBrowserSessions(ctx context.Context, userID int64) error {
	return m.Sessions.DeleteBrowserSessionsForUser(ctx, userID)
}
