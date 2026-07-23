package repo

import (
	"database/sql"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/network"

	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/lib/pq"
)

// UserAuthRepository defines the methods for inserting, updating and retrieving
// one time tokens (currently) used for email verification.
type UserAuthRepository struct {
	DB *sql.DB
}

// AddOTT saves the provided one time token for the specified user
func (repo *UserAuthRepository) AddOTT(emailHash string, app ente.App, ott string, expirationTime int64) error {
	_, err := repo.DB.Exec(`INSERT INTO otts(email_hash, ott, creation_time, expiration_time, app)
				VALUES($1, $2, $3, $4, $5)
				ON  CONFLICT ON CONSTRAINT unique_otts_emailhash_app_ott DO UPDATE SET creation_time = $3, expiration_time = $4`,
		emailHash, ott, time.Microseconds(), expirationTime, app)
	return stacktrace.Propagate(err, "")
}

// RemoveOTT removes the specified OTT and returns whether it was consumed.
func (repo *UserAuthRepository) RemoveOTT(emailHash string, ott string, app ente.App) (bool, error) {
	result, err := repo.DB.Exec(`DELETE FROM otts WHERE email_hash = $1 AND ott = $2 AND app = $3`, emailHash, ott, app)
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	return rowsAffected > 0, nil
}

// RemoveExpiredOTTs removes all OTTs that have expired
func (repo *UserAuthRepository) RemoveExpiredOTTs() error {
	_, err := repo.DB.Exec(`DELETE FROM otts WHERE expiration_time <= $1`,
		time.Microseconds())
	return stacktrace.Propagate(err, "")
}

// GetTokenCreationTime return the creation_time for the given token
func (repo *UserAuthRepository) GetTokenCreationTime(token string) (int64, error) {
	row := repo.DB.QueryRow(`SELECT creation_time from tokens where token = $1`, token)
	var result int64
	if err := row.Scan(&result); err != nil {
		return 0, stacktrace.Propagate(err, "Failed to scan row")
	}
	return result, nil
}

func (repo *UserAuthRepository) GetUserTokenInfo(userID int64) ([]ente.TokenInfo, error) {
	rows, err := repo.DB.Query(`SELECT creation_time, last_used_at, user_agent, is_deleted, app FROM tokens WHERE user_id = $1 AND is_deleted = false`, userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	tokenInfos := make([]ente.TokenInfo, 0)
	for rows.Next() {
		var tokenInfo ente.TokenInfo
		err := rows.Scan(&tokenInfo.CreationTime, &tokenInfo.LastUsedTime, &tokenInfo.UA, &tokenInfo.IsDeleted, &tokenInfo.App)
		if err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		tokenInfos = append(tokenInfos, tokenInfo)
	}
	return tokenInfos, nil
}

func (repo *UserAuthRepository) GetAppsForUser(userID int64) ([]ente.App, error) {
	rows, err := repo.DB.Query(`SELECT DISTINCT app FROM tokens WHERE user_id = $1`, userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	apps := make([]ente.App, 0)
	for rows.Next() {
		var app ente.App
		err := rows.Scan(&app)
		if err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		apps = append(apps, app)
	}
	return apps, nil
}

// GetValidOTTs returns the list of OTTs that haven't expired for a given user
func (repo *UserAuthRepository) GetValidOTTs(emailHash string, app ente.App) ([]string, error) {
	rows, err := repo.DB.Query(`SELECT ott FROM otts WHERE email_hash = $1 AND app = $2 AND expiration_time > $3`,
		emailHash, app, time.Microseconds())
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	otts := make([]string, 0)
	for rows.Next() {
		var ott string
		err := rows.Scan(&ott)
		if err != nil {
			return otts, stacktrace.Propagate(err, "")
		}
		otts = append(otts, ott)
	}

	return otts, nil
}

func (repo *UserAuthRepository) GetMaxWrongAttempts(emailHash string, app ente.App) (int, error) {
	row := repo.DB.QueryRow(`SELECT COALESCE(MAX(wrong_attempt),0) FROM otts WHERE email_hash = $1 AND expiration_time > $2 AND app = $3`,
		emailHash, time.Microseconds(), app)
	var wrongAttempt int
	if err := row.Scan(&wrongAttempt); err != nil {
		return 0, stacktrace.Propagate(err, "Failed to scan row")
	}
	return wrongAttempt, nil
}

// RecordWrongAttemptForActiveOtt increases the wrong_attempt count for given emailHash and active ott.
// Assuming tha we keep deleting expired OTT, max(wrong_attempt) can be used to track brute-force attack
func (repo *UserAuthRepository) RecordWrongAttemptForActiveOtt(emailHash string, app ente.App) error {
	_, err := repo.DB.Exec(`UPDATE otts SET wrong_attempt = otts.wrong_attempt + 1
				WHERE email_hash = $1  AND expiration_time > $2 AND app=$3`, emailHash, time.Microseconds(), app)
	if err != nil {
		return stacktrace.Propagate(err, "Failed to update wrong attempt count")
	}
	return nil
}

// AddToken saves the provided long lived token for the specified user
func (repo *UserAuthRepository) AddToken(userID int64, app ente.App, token string, ip string, userAgent string) error {
	_, err := repo.DB.Exec(`INSERT INTO tokens(user_id, app, token, creation_time, ip, user_agent) VALUES($1, $2, $3, $4, $5, $6)`,
		userID, app, token, time.Microseconds(), ip, userAgent)
	return stacktrace.Propagate(err, "")
}

// GetUserIDWithToken returns the userID associated with a given token and whether the token is expired
func (repo *UserAuthRepository) GetUserIDWithToken(token string, app ente.App) (int64, bool, error) {
	row := repo.DB.QueryRow(`
		SELECT 
			user_id,
			CASE 
				WHEN last_used_at IS NOT NULL AND last_used_at < (now_utc_micro_seconds() - (365::BIGINT * 24 * 60 * 60 * 1000 * 1000)) 
				THEN true 
				ELSE false 
			END as is_expired
		FROM tokens 
		WHERE token = $1 AND app = $2 AND is_deleted = false`, token, app)
	var id int64
	var isExpired bool
	err := row.Scan(&id, &isExpired)
	if err != nil {
		return -1, false, stacktrace.Propagate(err, "")
	}
	return id, isExpired, nil
}

// RemoveToken marks the specified token (to be used when a user logs out) as deleted
func (repo *UserAuthRepository) RemoveToken(userID int64, token string) error {
	_, err := repo.DB.Exec(`UPDATE tokens SET is_deleted = true WHERE user_id = $1 AND token = $2`,
		userID, token)
	return stacktrace.Propagate(err, "")
}

// UpdateLastUsedAt updates the last used at timestamp for the particular token
func (repo *UserAuthRepository) UpdateLastUsedAt(userID int64, token string, ip string, userAgent string) error {
	_, err := repo.DB.Exec(`UPDATE tokens SET ip = $1, user_agent = $2, last_used_at = $3 WHERE user_id = $4 AND token = $5`,
		ip, userAgent, time.Microseconds(), userID, token)
	return stacktrace.Propagate(err, "")
}

// RemoveAllOtherTokens marks the all tokens apart from the specified one for a user as deleted
func (repo *UserAuthRepository) RemoveAllOtherTokens(userID int64, token string) error {
	_, err := repo.DB.Exec(`UPDATE tokens SET is_deleted = true WHERE user_id = $1 AND token <> $2`,
		userID, token)
	return stacktrace.Propagate(err, "")
}

func (repo *UserAuthRepository) RemoveDeletedTokens(expiryTime int64) error {
	_, err := repo.DB.Exec(`DELETE FROM tokens WHERE is_deleted = true AND last_used_at < $1`, expiryTime)
	return stacktrace.Propagate(err, "")
}

// RemoveTokensForApps marks all tokens for the given apps as deleted for the user.
func (repo *UserAuthRepository) RemoveTokensForApps(userID int64, apps []ente.App) error {
	if len(apps) == 0 {
		return nil
	}
	dbApps := make([]string, 0, len(apps))
	for _, app := range apps {
		dbApps = append(dbApps, string(app))
	}
	_, err := repo.DB.Exec(`UPDATE tokens SET is_deleted = true WHERE user_id = $1 AND app = ANY($2)`,
		userID, pq.Array(dbApps))
	return stacktrace.Propagate(err, "")
}

// RemoveAllTokens marks the all tokens for a user as deleted
func (repo *UserAuthRepository) RemoveAllTokens(userID int64) error {
	_, err := repo.DB.Exec(`UPDATE tokens SET is_deleted = true WHERE user_id = $1`, userID)
	return stacktrace.Propagate(err, "")
}

// GetActiveSessions returns the list of tokens that are valid for a given user
func (repo *UserAuthRepository) GetActiveSessions(userID int64, app ente.App) ([]ente.Session, error) {
	rows, err := repo.DB.Query(`SELECT token, creation_time, ip, user_agent, last_used_at FROM tokens WHERE user_id = $1 AND app = $2 AND is_deleted = false`, userID, app)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	sessions := make([]ente.Session, 0)
	for rows.Next() {
		var ip sql.NullString
		var userAgent sql.NullString
		var session ente.Session
		err := rows.Scan(&session.Token, &session.CreationTime, &ip, &userAgent, &session.LastUsedTime)
		if err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		if ip.Valid {
			session.IP = ip.String
		} else {
			session.IP = "Unknown IP"
		}
		if userAgent.Valid {
			session.UA = userAgent.String
			session.PrettyUA = network.GetPrettyUA(userAgent.String)
		} else {
			session.UA = "Unknown Device"
			session.PrettyUA = "Unknown Device"
		}
		sessions = append(sessions, session)
	}
	return sessions, nil
}

// GetMinUserID returns the first user that was created in the system
func (repo *UserAuthRepository) GetMinUserID() (int64, error) {
	row := repo.DB.QueryRow(`select min(user_id) from users;`)
	var id int64
	err := row.Scan(&id)
	if err != nil {
		return -1, stacktrace.Propagate(err, "")
	}
	return id, nil
}
