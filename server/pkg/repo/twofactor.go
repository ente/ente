package repo

import (
	"database/sql"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/crypto"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
)

type TwoFactorRepository struct {
	DB                  *sql.DB
	SecretEncryptionKey []byte
}

// GetTwoFactorSecret gets the user's two factor secret
func (repo *TwoFactorRepository) GetTwoFactorSecret(userID int64) (string, error) {
	var encryptedTwoFASecret, nonce []byte
	row := repo.DB.QueryRow(`SELECT encrypted_two_factor_secret, two_factor_secret_decryption_nonce FROM two_factor WHERE user_id = $1`, userID)
	err := row.Scan(&encryptedTwoFASecret, &nonce)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	twoFASecret, err := crypto.Decrypt(encryptedTwoFASecret, repo.SecretEncryptionKey, nonce)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	return twoFASecret, nil
}

// UpdateTwoFactorStatus the activates/deactivates user's two factor
func (repo *TwoFactorRepository) UpdateTwoFactorStatus(userID int64, status bool) error {
	_, err := repo.DB.Exec(`UPDATE users SET is_two_factor_enabled = $1 WHERE user_id = $2`, status, userID)
	return stacktrace.Propagate(err, "")
}

// AddTwoFactorSession added a new two factor session a user
func (repo *TwoFactorRepository) AddTwoFactorSession(userID int64, sessionID string, expirationTime int64) error {
	_, err := repo.DB.Exec(`INSERT INTO two_factor_sessions(user_id, session_id, creation_time, expiration_time) VALUES($1, $2, $3, $4)`,
		userID, sessionID, time.Microseconds(), expirationTime)
	return stacktrace.Propagate(err, "")
}

// RemoveExpiredTwoFactorSessions removes all two factor sessions that have expired
func (repo *TwoFactorRepository) RemoveExpiredTwoFactorSessions() error {
	_, err := repo.DB.Exec(`DELETE FROM two_factor_sessions WHERE expiration_time <= $1`,
		time.Microseconds())
	return stacktrace.Propagate(err, "")
}

// GetUserIDWithTwoFactorSession returns the userID associated with a given session
func (repo *TwoFactorRepository) GetUserIDWithTwoFactorSession(sessionID string) (int64, error) {
	row := repo.DB.QueryRow(`SELECT user_id FROM two_factor_sessions WHERE session_id = $1 AND expiration_time > $2`, sessionID, time.Microseconds())
	var id int64
	err := row.Scan(&id)
	if err != nil {
		return -1, stacktrace.Propagate(err, "")
	}
	return id, nil
}

// GetRecoveryKeyEncryptedTwoFactorSecret gets the user two factor encrypted with recovery key
func (repo *TwoFactorRepository) GetRecoveryKeyEncryptedTwoFactorSecret(userID int64) (ente.TwoFactorRecoveryResponse, error) {
	var response ente.TwoFactorRecoveryResponse
	row := repo.DB.QueryRow(`SELECT recovery_encrypted_two_factor_secret, recovery_two_factor_secret_decryption_nonce FROM two_factor WHERE user_id = $1`, userID)
	err := row.Scan(&response.EncryptedSecret, &response.SecretDecryptionNonce)
	if err != nil {
		return ente.TwoFactorRecoveryResponse{}, stacktrace.Propagate(err, "")
	}
	return response, nil
}

// VerifyTwoFactorSecret verifies the if a two secret factor secret belongs to a user
func (repo *TwoFactorRepository) VerifyTwoFactorSecret(userID int64, secretHash string) (bool, error) {
	var exists bool
	row := repo.DB.QueryRow(`SELECT EXISTS( SELECT 1 FROM two_factor WHERE user_id = $1 AND two_factor_secret_hash = $2)`, userID, secretHash)
	err := row.Scan(&exists)
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	return exists, nil
}

// SetTempTwoFactorSecret sets the two factor secret for a user when he tries to setup a new two-factor app
func (repo *TwoFactorRepository) SetTempTwoFactorSecret(userID int64, secret ente.EncryptionResult, secretHash string, expirationTime int64) error {
	_, err := repo.DB.Exec(`INSERT INTO temp_two_factor(user_id, encrypted_two_factor_secret, two_factor_secret_decryption_nonce, two_factor_secret_hash, creation_time, expiration_time) 
		VALUES($1, $2, $3, $4, $5, $6)`,
		userID, secret.Cipher, secret.Nonce, secretHash, time.Microseconds(), expirationTime)
	return stacktrace.Propagate(err, "")
}

// GetTempTwoFactorSecret gets the user's two factor secret for validing and enabling a new two-factor configuration
func (repo *TwoFactorRepository) GetTempTwoFactorSecret(userID int64) ([]ente.EncryptionResult, []string, error) {
	rows, err := repo.DB.Query(`SELECT encrypted_two_factor_secret, two_factor_secret_decryption_nonce, two_factor_secret_hash FROM temp_two_factor WHERE user_id = $1 AND expiration_time > $2`, userID, time.Microseconds())
	if err != nil {
		return make([]ente.EncryptionResult, 0), make([]string, 0), stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	encryptedSecrets := make([]ente.EncryptionResult, 0)
	hashedSecrets := make([]string, 0)
	for rows.Next() {
		var encryptedTwoFASecret ente.EncryptionResult
		var secretHash string
		err := rows.Scan(&encryptedTwoFASecret.Cipher, &encryptedTwoFASecret.Nonce, &secretHash)
		if err != nil {
			return make([]ente.EncryptionResult, 0), make([]string, 0), stacktrace.Propagate(err, "")
		}
		encryptedSecrets = append(encryptedSecrets, encryptedTwoFASecret)
		hashedSecrets = append(hashedSecrets, secretHash)
	}
	return encryptedSecrets, hashedSecrets, nil
}

// RemoveTempTwoFactorSecret removes the specified secret with hash value `secretHash`
func (repo *TwoFactorRepository) RemoveTempTwoFactorSecret(secretHash string) error {
	_, err := repo.DB.Exec(`DELETE FROM temp_two_factor WHERE two_factor_secret_hash = $1`, secretHash)
	return stacktrace.Propagate(err, "")
}

// RemoveExpiredTempTwoFactorSecrets removes all two temp factor secrets  that have expired
func (repo *TwoFactorRepository) RemoveExpiredTempTwoFactorSecrets() error {
	_, err := repo.DB.Exec(`DELETE FROM temp_two_factor WHERE expiration_time <= $1`,
		time.Microseconds())
	return stacktrace.Propagate(err, "")
}

// GetWrongAttempts returns the wrong attempt count for the given two factor session
func (repo *TwoFactorRepository) GetWrongAttempts(sessionID string) (int, error) {
	row := repo.DB.QueryRow(`SELECT wrong_attempt FROM two_factor_sessions WHERE session_id = $1`,
		sessionID)
	var wrongAttempt int
	if err := row.Scan(&wrongAttempt); err != nil {
		return 0, stacktrace.Propagate(err, "Failed to scan row")
	}
	return wrongAttempt, nil
}

// RecordWrongAttempt increases the wrong_attempt count for the given two factor session.
// This is used to track and prevent brute-force attacks on two-factor verification
func (repo *TwoFactorRepository) RecordWrongAttempt(sessionID string) error {
	_, err := repo.DB.Exec(`UPDATE two_factor_sessions SET wrong_attempt = wrong_attempt + 1
			WHERE session_id = $1`, sessionID)
	if err != nil {
		return stacktrace.Propagate(err, "Failed to update wrong attempt count")
	}
	return nil
}

// TryRecordUsedOTPCode atomically tries to record an OTP code as used
// Returns true if the code was newly recorded, false if it already existed (replay attack)
func (repo *TwoFactorRepository) TryRecordUsedOTPCode(userID int64, codeHash string) (bool, error) {
	result, err := repo.DB.Exec(`INSERT INTO two_factor_used_codes(user_id, code_hash, used_at)
		VALUES($1, $2, $3) ON CONFLICT (user_id, code_hash) DO NOTHING`,
		userID, codeHash, time.Microseconds())
	if err != nil {
		return false, stacktrace.Propagate(err, "Failed to record used OTP code")
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return false, stacktrace.Propagate(err, "Failed to get rows affected")
	}

	return rowsAffected > 0, nil
}

// RemoveExpiredUsedOTPCodes removes OTP codes older than the specified duration
func (repo *TwoFactorRepository) RemoveExpiredUsedOTPCodes(expirationMicroseconds int64) error {
	cutoffTime := time.Microseconds() - expirationMicroseconds
	_, err := repo.DB.Exec(`DELETE FROM two_factor_used_codes WHERE used_at < $1`, cutoffTime)
	if err != nil {
		return stacktrace.Propagate(err, "Failed to remove expired used OTP codes")
	}
	return nil
}
