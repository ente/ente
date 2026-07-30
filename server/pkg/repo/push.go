package repo

import (
	"database/sql"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

type PushTokenRepository struct {
	DB *sql.DB
}

func (repo *PushTokenRepository) AddToken(userID int64, token ente.PushTokenRequest) error {
	_, err := repo.DB.Exec(`INSERT INTO push_tokens(user_id, fcm_token, apns_token) VALUES($1, $2, $3) 
			ON CONFLICT (fcm_token) DO UPDATE
			SET apns_token = $3`,
		userID, token.FCMToken, token.APNSToken)
	return stacktrace.Propagate(err, "")
}

func (repo *PushTokenRepository) GetTokensToBeNotified(lastNotificationTime int64, limit int) ([]ente.PushToken, error) {
	rows, err := repo.DB.Query(`SELECT user_id, fcm_token, created_at, last_notified_at FROM push_tokens WHERE last_notified_at < $1 LIMIT $2`, lastNotificationTime, limit)
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
