package repo

import (
	"context"
	"database/sql"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

type PushTokenRepository struct {
	DB *sql.DB
}

func (repo *PushTokenRepository) AddToken(userID int64, sessionTokenHash []byte, token ente.PushTokenRequest) error {
	result, err := repo.DB.Exec(`INSERT INTO push_tokens(user_id, fcm_token, apns_token, session_token_hash, platform)
			SELECT user_id, $2, $3, token_hash, $5 FROM tokens
			WHERE user_id = $1 AND token_hash = $4 AND is_deleted = false FOR SHARE
			ON CONFLICT (fcm_token) DO UPDATE
			SET user_id = EXCLUDED.user_id, apns_token = EXCLUDED.apns_token, session_token_hash = EXCLUDED.session_token_hash,
				platform = EXCLUDED.platform`,
		userID, token.FCMToken, token.APNSToken, sessionTokenHash, token.Platform)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	count, err := result.RowsAffected()
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if count == 0 {
		return ente.ErrAuthenticationRequired
	}
	return nil
}

func (repo *PushTokenRepository) GetTokensToBeNotified(lastNotificationTime int64, limit int) ([]ente.PushToken, error) {
	rows, err := repo.DB.Query(`SELECT p.user_id, p.fcm_token, p.created_at, p.last_notified_at FROM push_tokens p
		WHERE p.last_notified_at < $1 AND p.platform = 'ios'
		AND (p.session_token_hash IS NULL OR EXISTS (
			SELECT 1 FROM tokens t WHERE t.token_hash = p.session_token_hash
			AND t.user_id = p.user_id AND t.is_deleted = false
		)) LIMIT $2`, lastNotificationTime, limit)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	tokens := make([]ente.PushToken, 0)
	for rows.Next() {
		var token ente.PushToken
		err = rows.Scan(&token.UserID, &token.FCMToken, &token.CreatedAt, &token.LastNotifiedAt)
		if err != nil {
			return tokens, stacktrace.Propagate(err, "")
		}
		tokens = append(tokens, token)
	}
	return tokens, nil
}

func (repo *PushTokenRepository) GetTokensForAlbumShare(ctx context.Context, userIDs []int64) ([]ente.PushToken, error) {
	rows, err := repo.DB.QueryContext(ctx, `SELECT p.fcm_token FROM push_tokens p
		JOIN tokens t ON t.token_hash = p.session_token_hash AND t.user_id = p.user_id AND t.is_deleted = false AND t.app = $3
		JOIN remote_store r ON r.user_id = p.user_id AND r.key_name = $2 AND r.key_value = 'true'
		WHERE p.user_id = ANY($1) AND p.platform = 'android'`,
		pq.Array(userIDs), string(ente.IsInternalUser), string(ente.Photos))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	var tokens []ente.PushToken
	for rows.Next() {
		var token ente.PushToken
		if err := rows.Scan(&token.FCMToken); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		tokens = append(tokens, token)
	}
	return tokens, stacktrace.Propagate(rows.Err(), "")
}

func (repo *PushTokenRepository) SetLastNotificationTimeToNow(pushTokens []ente.PushToken) error {
	fcmTokens := make([]string, 0)
	for _, pushToken := range pushTokens {
		fcmTokens = append(fcmTokens, pushToken.FCMToken)
	}
	_, err := repo.DB.Exec(`UPDATE push_tokens SET last_notified_at = $1 WHERE fcm_token = ANY($2)`, time.Microseconds(), pq.Array(fcmTokens))
	return stacktrace.Propagate(err, "Could not set last notification time")
}

func (repo *PushTokenRepository) RemoveTokensOlderThan(creationTime int64) error {
	_, err := repo.DB.Exec(`DELETE FROM push_tokens WHERE updated_at <= $1`, creationTime)
	return stacktrace.Propagate(err, "")
}

func (repo *PushTokenRepository) RemoveTokensByFCM(fcmTokens []string) error {
	_, err := repo.DB.Exec(`DELETE FROM push_tokens WHERE fcm_token = ANY($1)`, pq.Array(fcmTokens))
	return stacktrace.Propagate(err, "")
}

func (repo *PushTokenRepository) RemoveTokensForUser(userID int64) error {
	// Does a seq scan but should be fine since this is relatively infrequent
	// and the size of the push tokens table will be small (as it gets
	// periodically pruned).
	_, err := repo.DB.Exec(`DELETE FROM push_tokens WHERE user_id = $1`, userID)
	return stacktrace.Propagate(err, "")
}
