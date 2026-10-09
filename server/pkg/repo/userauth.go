package repo

import (
	"context"
	"database/sql"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/auth"
	"github.com/ente/museum/pkg/utils/network"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/google/uuid"
	"github.com/lib/pq"
)

type UserAuthRepository struct {
	DB *sql.DB
}

type RevokedToken struct {
	App       ente.App
	TokenHash []byte
}

type PendingLoginSession int

const (
	NoPendingLogin PendingLoginSession = iota
	TOTPPendingLogin
	PasskeyPendingLogin
)

func (repo *UserAuthRepository) AddOTT(emailHash string, app ente.App, ott string, expirationTime int64) error {
	_, err := repo.DB.Exec(`INSERT INTO otts(email_hash, ott, creation_time, expiration_time, app)
				VALUES($1, $2, $3, $4, $5)
				ON  CONFLICT ON CONSTRAINT unique_otts_emailhash_app_ott DO UPDATE SET creation_time = $3, expiration_time = $4`,
		emailHash, ott, time.Microseconds(), expirationTime, app)
	return stacktrace.Propagate(err, "")
}

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

func (repo *UserAuthRepository) RemoveExpiredOTTs() error {
	_, err := repo.DB.Exec(`DELETE FROM otts WHERE expiration_time <= $1`,
		time.Microseconds())
	return stacktrace.Propagate(err, "")
}

func (repo *UserAuthRepository) GetTokenCreationTimeByHash(tokenHash []byte) (int64, error) {
	row := repo.DB.QueryRow(`SELECT creation_time from tokens where token_hash = $1`, tokenHash)
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

func (repo *UserAuthRepository) ReserveOTTVerificationAttempt(emailHash string, app ente.App, submittedOTT string, limit int) ([]string, bool, error) {
	tx, err := repo.DB.Begin()
	if err != nil {
		return nil, false, stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()

	rows, err := tx.Query(`SELECT ott, wrong_attempt FROM otts
		WHERE email_hash = $1 AND app = $2 AND expiration_time > $3
		ORDER BY ott FOR UPDATE`, emailHash, app, time.Microseconds())
	if err != nil {
		return nil, false, stacktrace.Propagate(err, "")
	}
	defer rows.Close()

	otts := make([]string, 0)
	limited := false
	matched := false
	for rows.Next() {
		var ott string
		var wrongAttempt int
		if err := rows.Scan(&ott, &wrongAttempt); err != nil {
			return nil, false, stacktrace.Propagate(err, "")
		}
		otts = append(otts, ott)
		limited = limited || wrongAttempt >= limit
		matched = matched || ott == submittedOTT
	}
	if err := rows.Err(); err != nil {
		return nil, false, stacktrace.Propagate(err, "")
	}
	if limited || len(otts) == 0 || matched {
		return otts, limited, nil
	}

	_, err = tx.Exec(`UPDATE otts SET wrong_attempt = wrong_attempt + 1
		WHERE email_hash = $1 AND app = $2 AND ott = ANY($3)`, emailHash, app, pq.Array(otts))
	if err != nil {
		return nil, false, stacktrace.Propagate(err, "")
	}
	if err := tx.Commit(); err != nil {
		return nil, false, stacktrace.Propagate(err, "")
	}
	return otts, false, nil
}

func (repo *UserAuthRepository) AddToken(userID int64, app ente.App, token string, ip string, userAgent string) error {
	tokenHash := auth.HashToken(token)
	_, err := repo.DB.Exec(`INSERT INTO tokens(user_id, app, token_hash, creation_time, ip, user_agent) VALUES($1, $2, $3, $4, $5, $6)`,
		userID, app, tokenHash[:], time.Microseconds(), ip, userAgent)
	return stacktrace.Propagate(err, "")
}

func (repo *UserAuthRepository) AddLoginResult(ctx context.Context, userID int64, srpAuth *ente.SRPAuthEntity, expectedKeyAttributes *ente.KeyAttributes,
	app ente.App, token, ip, userAgent, passkeySessionID, twoFactorSessionID string, expirationTime int64,
) error {
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()
	if err = lockUserForLogin(ctx, tx, userID, srpAuth, expectedKeyAttributes); err != nil {
		return err
	}
	now := time.Microseconds()
	if passkeySessionID != "" {
		if _, err = tx.ExecContext(ctx, `INSERT INTO passkey_login_sessions(user_id, session_id, creation_time, expiration_time) VALUES($1, $2, $3, $4)`, userID, passkeySessionID, now, expirationTime); err != nil {
			return stacktrace.Propagate(err, "")
		}
	}
	if twoFactorSessionID != "" {
		if _, err = tx.ExecContext(ctx, `INSERT INTO two_factor_sessions(user_id, session_id, creation_time, expiration_time) VALUES($1, $2, $3, $4)`, userID, twoFactorSessionID, now, expirationTime); err != nil {
			return stacktrace.Propagate(err, "")
		}
	}
	if token != "" {
		tokenHash := auth.HashToken(token)
		if _, err = tx.ExecContext(ctx, `INSERT INTO tokens(user_id, app, token_hash, creation_time, ip, user_agent) VALUES($1, $2, $3, $4, $5, $6)`, userID, app, tokenHash[:], now, ip, userAgent); err != nil {
			return stacktrace.Propagate(err, "")
		}
	}
	return stacktrace.Propagate(tx.Commit(), "")
}

func (repo *UserAuthRepository) AddTokenForPendingLogin(ctx context.Context, userID int64, sessionID string,
	session PendingLoginSession, disableTwoFactor bool, app ente.App, token, ip, userAgent string, tokenData []byte,
) error {
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()
	if err = lockUserForLogin(ctx, tx, userID, nil, nil); err != nil {
		return err
	}
	now := time.Microseconds()
	sessionQuery := `DELETE FROM two_factor_sessions WHERE session_id = $1 AND user_id = $2 AND expiration_time > $3 RETURNING user_id`
	sessionArgs := []interface{}{sessionID, userID, now}
	if session == PasskeyPendingLogin {
		sessionQuery = `DELETE FROM passkey_login_sessions WHERE session_id = $1 AND user_id = $2 AND expiration_time > $3 AND verified_at IS NULL RETURNING user_id`
		if len(tokenData) != 0 {
			sessionQuery = `UPDATE passkey_login_sessions SET token_data = $4, verified_at = $3 WHERE session_id = $1 AND user_id = $2 AND expiration_time > $3 AND verified_at IS NULL RETURNING user_id`
			sessionArgs = append(sessionArgs, tokenData)
		}
	}
	var sessionUserID int64
	if err = tx.QueryRowContext(ctx, sessionQuery, sessionArgs...).Scan(&sessionUserID); err != nil {
		return stacktrace.Propagate(err, "")
	}
	if disableTwoFactor {
		if _, err = tx.ExecContext(ctx, `UPDATE users SET is_two_factor_enabled = false WHERE user_id = $1`, userID); err != nil {
			return stacktrace.Propagate(err, "")
		}
	}
	tokenHash := auth.HashToken(token)
	if _, err = tx.ExecContext(ctx, `INSERT INTO tokens(user_id, app, token_hash, creation_time, ip, user_agent) VALUES($1, $2, $3, $4, $5, $6)`, userID, app, tokenHash[:], now, ip, userAgent); err != nil {
		return stacktrace.Propagate(err, "")
	}
	return stacktrace.Propagate(tx.Commit(), "")
}

func lockUserForLogin(ctx context.Context, tx *sql.Tx, userID int64, srpAuth *ente.SRPAuthEntity, expectedKeyAttributes *ente.KeyAttributes) error {
	var active bool
	if err := tx.QueryRowContext(ctx, `SELECT encrypted_email IS NOT NULL FROM users WHERE user_id = $1 FOR NO KEY UPDATE`, userID).Scan(&active); err != nil {
		return stacktrace.Propagate(err, "")
	}
	if !active {
		return stacktrace.Propagate(ente.ErrUserDeleted, "")
	}
	if srpAuth != nil {
		var currentSRPUserID uuid.UUID
		var currentSRPSalt string
		var currentSRPVerifier string
		if err := tx.QueryRowContext(ctx, `SELECT srp_user_id, salt, verifier FROM srp_auth WHERE user_id = $1`, userID).Scan(&currentSRPUserID, &currentSRPSalt, &currentSRPVerifier); err != nil {
			if err == sql.ErrNoRows {
				return stacktrace.Propagate(ente.ErrInvalidPassword, "stale SRP login")
			}
			return stacktrace.Propagate(err, "")
		}
		if currentSRPUserID != srpAuth.SRPUserID || currentSRPSalt != srpAuth.Salt || currentSRPVerifier != srpAuth.Verifier {
			return stacktrace.Propagate(ente.ErrInvalidPassword, "stale SRP login")
		}
	}
	if expectedKeyAttributes != nil {
		var matches bool
		err := tx.QueryRowContext(ctx, `SELECT EXISTS (SELECT 1 FROM key_attributes WHERE user_id = $1 AND kek_salt = $2 AND encrypted_key = $3 AND key_decryption_nonce = $4 AND mem_limit = $5 AND ops_limit = $6)`,
			userID, expectedKeyAttributes.KEKSalt, expectedKeyAttributes.EncryptedKey, expectedKeyAttributes.KeyDecryptionNonce, expectedKeyAttributes.MemLimit, expectedKeyAttributes.OpsLimit).Scan(&matches)
		if err != nil {
			return stacktrace.Propagate(err, "")
		}
		if !matches {
			return stacktrace.Propagate(ente.ErrAuthenticationRequired, "key attributes changed during login")
		}
	}
	return nil
}

func (repo *UserAuthRepository) GetUserIDWithTokenHash(tokenHash []byte, app ente.App) (int64, bool, error) {
	row := repo.DB.QueryRow(`
		SELECT 
			user_id,
			CASE 
				WHEN last_used_at IS NOT NULL AND last_used_at < (now_utc_micro_seconds() - (365::BIGINT * 24 * 60 * 60 * 1000 * 1000)) 
				THEN true 
				ELSE false 
			END as is_expired
		FROM tokens 
		WHERE token_hash = $1 AND app = $2 AND is_deleted = false`, tokenHash, app)
	var id int64
	var isExpired bool
	err := row.Scan(&id, &isExpired)
	if err != nil {
		return -1, false, stacktrace.Propagate(err, "")
	}
	return id, isExpired, nil
}

func (repo *UserAuthRepository) RemoveTokenByHash(userID int64, tokenHash []byte) ([]RevokedToken, error) {
	return repo.markTokensDeleted(
		`UPDATE tokens SET is_deleted = true WHERE user_id = $1 AND token_hash = $2 RETURNING app, token_hash`,
		userID, tokenHash,
	)
}

func (repo *UserAuthRepository) UpdateLastUsedAtByTokenHash(userID int64, tokenHash []byte, ip string, userAgent string) error {
	_, err := repo.DB.Exec(`UPDATE tokens SET ip = $1, user_agent = $2, last_used_at = $3 WHERE user_id = $4 AND token_hash = $5`,
		ip, userAgent, time.Microseconds(), userID, tokenHash)
	return stacktrace.Propagate(err, "")
}

func (repo *UserAuthRepository) RemoveAllOtherTokensByHash(userID int64, tokenHash []byte) ([]RevokedToken, error) {
	return repo.markTokensDeleted(
		`UPDATE tokens SET is_deleted = true WHERE user_id = $1 AND token_hash <> $2 AND is_deleted = false RETURNING app, token_hash`,
		userID, tokenHash,
	)
}

func (repo *UserAuthRepository) RemoveDeletedTokens(expiryTime int64) error {
	_, err := repo.DB.Exec(`DELETE FROM tokens WHERE is_deleted = true AND last_used_at < $1`, expiryTime)
	return stacktrace.Propagate(err, "")
}

func (repo *UserAuthRepository) RemoveTokensForApps(userID int64, apps []ente.App) ([]RevokedToken, error) {
	if len(apps) == 0 {
		return nil, nil
	}
	dbApps := make([]string, 0, len(apps))
	for _, app := range apps {
		dbApps = append(dbApps, string(app))
	}
	return repo.markTokensDeleted(
		`UPDATE tokens SET is_deleted = true WHERE user_id = $1 AND app = ANY($2) AND is_deleted = false RETURNING app, token_hash`,
		userID, pq.Array(dbApps),
	)
}

func (repo *UserAuthRepository) markTokensDeleted(query string, args ...interface{}) ([]RevokedToken, error) {
	tx, err := repo.DB.Begin()
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()
	tokens, err := markTokensDeleted(tx, query, args...)
	if err != nil {
		return nil, err
	}
	if err = tx.Commit(); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return tokens, nil
}

func markTokensDeleted(tx *sql.Tx, query string, args ...interface{}) ([]RevokedToken, error) {
	rows, err := tx.Query(query, args...)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()

	tokens := make([]RevokedToken, 0)
	var hashes pq.ByteaArray
	for rows.Next() {
		var token RevokedToken
		if err = rows.Scan(&token.App, &token.TokenHash); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		tokens = append(tokens, token)
		hashes = append(hashes, token.TokenHash)
	}
	if err = rows.Err(); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if _, err = tx.Exec(`DELETE FROM push_tokens WHERE session_token_hash = ANY($1)`, hashes); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return tokens, nil
}

func (repo *UserAuthRepository) GetActiveSessions(userID int64, app ente.App) ([]ente.Session, error) {
	rows, err := repo.DB.Query(`SELECT token_hash, creation_time, ip, user_agent, last_used_at FROM tokens WHERE user_id = $1 AND app = $2 AND is_deleted = false`, userID, app)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	sessions := make([]ente.Session, 0)
	for rows.Next() {
		var ip sql.NullString
		var userAgent sql.NullString
		var session ente.Session
		err := rows.Scan(&session.TokenHash, &session.CreationTime, &ip, &userAgent, &session.LastUsedTime)
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

func (repo *UserAuthRepository) GetMinUserID() (int64, error) {
	row := repo.DB.QueryRow(`select min(user_id) from users;`)
	var id int64
	err := row.Scan(&id)
	if err != nil {
		return -1, stacktrace.Propagate(err, "")
	}
	return id, nil
}
