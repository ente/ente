package repo

import (
	"context"
	"database/sql"
	"errors"

	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
	"github.com/google/uuid"
	log "github.com/sirupsen/logrus"
)

type PasswordUpdateAuthorization func(context.Context, *sql.Tx) error

func (repo *UserAuthRepository) AddSRPSession(srpUserID uuid.UUID, serverKey string, srpA string) (uuid.UUID, error) {
	id := uuid.New()
	_, err := repo.DB.Exec(`
	INSERT INTO srp_sessions(id, srp_user_id, server_key, srp_a)
	 VALUES($1, $2 , $3, $4)`, id, srpUserID, serverKey, srpA)
	return id, stacktrace.Propagate(err, "")
}

// AddFakeSRPSession inserts a fake SRPSession for user enumeration protection
func (repo *UserAuthRepository) AddFakeSRPSession(srpUserID uuid.UUID, serverKey string, srpA string) (uuid.UUID, error) {
	id := uuid.New()
	_, err := repo.DB.Exec(`
	INSERT INTO srp_sessions(id, srp_user_id, server_key, srp_a, is_fake)
	 VALUES($1, $2 , $3, $4, true)`, id, srpUserID, serverKey, srpA)
	return id, stacktrace.Propagate(err, "")
}

func (repo *UserAuthRepository) GetUnverifiedSessionsInLastHour(srpUserID uuid.UUID) (int64, error) {
	var count int64
	err := repo.DB.QueryRow(`SELECT COUNT(*) FROM srp_sessions WHERE srp_user_id = $1 AND has_verified = false AND created_at > (now_utc_micro_seconds() - (60::BIGINT * 60 * 1000 * 1000))`, srpUserID).Scan(&count)
	return count, stacktrace.Propagate(err, "")
}

func (repo *UserAuthRepository) GetSRPAuthEntity(ctx context.Context, userID int64) (*ente.SRPAuthEntity, error) {
	result := ente.SRPAuthEntity{}
	row := repo.DB.QueryRowContext(ctx, `SELECT user_id, srp_user_id, salt, verifier FROM srp_auth WHERE user_id = $1`, userID)
	err := row.Scan(&result.UserID, &result.SRPUserID, &result.Salt, &result.Verifier)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &result, nil
}

func (repo *UserAuthRepository) GetSRPAuthEntityBySRPUserID(ctx context.Context, srpUserID uuid.UUID) (*ente.SRPAuthEntity, error) {
	result := ente.SRPAuthEntity{}
	row := repo.DB.QueryRowContext(ctx, `SELECT user_id, srp_user_id, salt, verifier FROM srp_auth WHERE srp_user_id = $1`, srpUserID)
	err := row.Scan(&result.UserID, &result.SRPUserID, &result.Salt, &result.Verifier)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &result, nil

}

func (repo *UserAuthRepository) IsSRPSetupDone(ctx context.Context, userID int64) (bool, error) {
	_, err := repo.GetSRPAuthEntity(ctx, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return false, nil
		}
		return false, stacktrace.Propagate(err, "failed to read srp attributes")
	}
	return true, nil
}

func (repo *UserAuthRepository) UpdateEmailMFA(ctx context.Context, userID int64, isEnabled bool) error {
	_, err := repo.DB.ExecContext(ctx, `UPDATE users SET email_mfa = $1 WHERE user_id = $2`, isEnabled, userID)
	if err != nil {
		return stacktrace.Propagate(err, "failed to update email MFA status")
	}
	return nil
}

func (repo *UserAuthRepository) IsEmailMFAEnabled(ctx context.Context, userID int64) (*bool, error) {
	row := repo.DB.QueryRowContext(ctx, `SELECT email_mfa FROM users WHERE user_id = $1`, userID)
	var isEnabled bool
	err := row.Scan(&isEnabled)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &isEnabled, nil
}

func (repo *UserAuthRepository) InsertTempSRPSetup(ctx context.Context, req ente.SetupSRPRequest, userID int64, sessionID *uuid.UUID) (*uuid.UUID, error) {
	id := uuid.New()
	_, err := repo.DB.ExecContext(ctx, `
	INSERT INTO temp_srp_setup(id, session_id, user_id, srp_user_id, salt, verifier) VALUES($1, $2 , $3, $4, $5, $6)`,
		id, sessionID, userID, req.SrpUserID, req.SRPSalt, req.SRPVerifier)
	return &id, stacktrace.Propagate(err, "")
}

func (repo *UserAuthRepository) GetTempSRPSetupEntity(ctx context.Context, setUpID uuid.UUID, userID int64) (*ente.SRPSetupEntity, error) {
	result := ente.SRPSetupEntity{}
	row := repo.DB.QueryRowContext(ctx, `SELECT id, session_id, user_id, srp_user_id, salt, verifier FROM temp_srp_setup WHERE id = $1 AND user_id = $2`, setUpID, userID)
	err := row.Scan(&result.ID, &result.SessionID, &result.UserID, &result.SRPUserID, &result.Salt, &result.Verifier)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &result, nil
}

func (repo *UserAuthRepository) InsertSRPAuth(ctx context.Context, userID int64, srpUserID uuid.UUID, verifier string, salt string) error {
	isSRPSetupDone, err := repo.IsSRPSetupDone(ctx, userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if isSRPSetupDone {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("SRP setup already complete"), "")
	}
	_, err = repo.DB.ExecContext(ctx, `
	INSERT INTO srp_auth(user_id, srp_user_id, salt, verifier) VALUES($1, $2 , $3, $4)`,
		userID, srpUserID, salt, verifier)
	return stacktrace.Propagate(err, "")
}

func (repo *UserAuthRepository) InsertOrUpdateSRPAuthAndKeyAttr(ctx context.Context, userID int64, updateKeyAttr ente.UpdateKeysRequest,
	setup *ente.SRPSetupEntity, clearTokens bool, currentTokenHash []byte, disableSecondFactors bool, authorize PasswordUpdateAuthorization,
) ([]RevokedToken, error) {
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer tx.Rollback()
	if err = lockUserForLogin(ctx, tx, userID, nil, nil); err != nil {
		return nil, err
	}
	if len(currentTokenHash) != 0 {
		var tokenUserID int64
		if err = tx.QueryRowContext(ctx, `SELECT user_id FROM tokens WHERE user_id = $1 AND token_hash = $2 AND is_deleted = false`, userID, currentTokenHash).Scan(&tokenUserID); err != nil {
			if err == sql.ErrNoRows {
				return nil, stacktrace.Propagate(ente.ErrAuthenticationRequired, "token revoked during password update")
			}
			return nil, stacktrace.Propagate(err, "")
		}
	}
	if authorize != nil {
		if err = authorize(ctx, tx); err != nil {
			return nil, err
		}
	}
	if disableSecondFactors {
		if _, err = tx.ExecContext(ctx, `UPDATE users SET is_two_factor_enabled = false WHERE user_id = $1`, userID); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		if _, err = tx.ExecContext(ctx, `UPDATE passkeys SET friendly_name = id::text, deleted_at = now_utc_micro_seconds() WHERE user_id = $1 AND deleted_at IS NULL`, userID); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
	}
	_, err = tx.ExecContext(ctx, `
		INSERT INTO srp_auth(user_id, srp_user_id, salt, verifier) VALUES($1, $2, $3, $4)
		ON CONFLICT (user_id) DO UPDATE SET
			srp_user_id = EXCLUDED.srp_user_id, salt = EXCLUDED.salt, verifier = EXCLUDED.verifier`,
		userID, setup.SRPUserID, setup.Salt, setup.Verifier)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `UPDATE key_attributes SET kek_salt = $1, encrypted_key = $2, key_decryption_nonce = $3, mem_limit = $4, ops_limit = $5 WHERE user_id = $6`,
		updateKeyAttr.KEKSalt, updateKeyAttr.EncryptedKey, updateKeyAttr.KeyDecryptionNonce, updateKeyAttr.MemLimit, updateKeyAttr.OpsLimit, userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `
		WITH deleted_two_factor_sessions AS (
			DELETE FROM two_factor_sessions WHERE user_id = $1
		)
		DELETE FROM passkey_login_sessions WHERE user_id = $1 AND ($2 OR verified_at IS NULL)`, userID, clearTokens)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	var revokedTokens []RevokedToken
	if clearTokens {
		query := `UPDATE tokens SET is_deleted = true WHERE user_id = $1 AND is_deleted = false RETURNING app, token_hash`
		args := []interface{}{userID}
		if len(currentTokenHash) != 0 {
			query = `UPDATE tokens SET is_deleted = true WHERE user_id = $1 AND token_hash <> $2 AND is_deleted = false RETURNING app, token_hash`
			args = append(args, currentTokenHash)
		}
		revokedTokens, err = markTokensDeleted(tx, query, args...)
		if err != nil {
			return nil, err
		}
	}
	if err = tx.Commit(); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return revokedTokens, nil
}

func (repo *UserAuthRepository) GetSrpSessionEntity(ctx context.Context, sessionID uuid.UUID) (*ente.SRPSessionEntity, error) {
	result := ente.SRPSessionEntity{}
	row := repo.DB.QueryRowContext(ctx, `SELECT id, srp_user_id, server_key, srp_a, has_verified, attempt_count, COALESCE(is_fake, false) FROM srp_sessions WHERE id = $1`, sessionID)
	err := row.Scan(&result.ID, &result.SRPUserID, &result.ServerKey, &result.SRP_A, &result.IsVerified, &result.AttemptCount, &result.IsFake)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &result, nil
}

func (repo *UserAuthRepository) ReserveSrpSessionAttempt(ctx context.Context, sessionID uuid.UUID, limit int) (*ente.SRPSessionEntity, error) {
	result := ente.SRPSessionEntity{}
	row := repo.DB.QueryRowContext(ctx, `UPDATE srp_sessions SET attempt_count = attempt_count + 1
		WHERE id = $1 AND has_verified = false AND attempt_count < $2
		RETURNING id, srp_user_id, server_key, srp_a, has_verified, attempt_count, COALESCE(is_fake, false)`, sessionID, limit)
	err := row.Scan(&result.ID, &result.SRPUserID, &result.ServerKey, &result.SRP_A, &result.IsVerified, &result.AttemptCount, &result.IsFake)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &result, nil
}

func (repo *UserAuthRepository) TrySetSrpSessionVerified(ctx context.Context, sessionID uuid.UUID) (bool, error) {
	result, err := repo.DB.ExecContext(ctx, `UPDATE srp_sessions SET has_verified = true WHERE id = $1 AND has_verified = false`, sessionID)
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	return rowsAffected == 1, nil
}

func (repo *UserAuthRepository) CleanupOldSRPSessions(ctx context.Context, batchSize int) (int64, error) {
	result, err := repo.DB.ExecContext(ctx, `
		WITH old_sessions AS (
			SELECT id
			FROM srp_sessions
			WHERE created_at < (now_utc_micro_seconds() - (24::BIGINT * 60 * 60 * 1000 * 1000))
			ORDER BY created_at
			LIMIT $1
			FOR UPDATE SKIP LOCKED
		)
		DELETE FROM srp_sessions
		USING old_sessions
		WHERE srp_sessions.id = old_sessions.id`, batchSize)
	if err != nil {
		return 0, stacktrace.Propagate(err, "failed to cleanup old SRP sessions")
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return 0, stacktrace.Propagate(err, "failed to get rows affected")
	}
	return rowsAffected, nil
}

func (repo *UserAuthRepository) GetSRPAttributes(userID int64) (*ente.GetSRPAttributesResponse, error) {
	row := repo.DB.QueryRow(`SELECT  srp_user_id, salt, mem_limit, ops_limit, kek_salt, email_mfa FROM srp_auth left join key_attributes on srp_auth.user_id = key_attributes.user_id 
                                                                     left join users on users.user_id = srp_auth.user_id  WHERE srp_auth.user_id = $1`, userID)
	var srpAttributes ente.GetSRPAttributesResponse
	err := row.Scan(&srpAttributes.SRPUserID, &srpAttributes.SRPSalt, &srpAttributes.MemLimit, &srpAttributes.OpsLimit, &srpAttributes.KekSalt, &srpAttributes.IsEmailMFAEnabled)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, stacktrace.Propagate(&ente.ErrNotFoundError, "srp attributes are not present")
		}
		if err.Error() == "sql: Scan error on column index 2, name \"mem_limit\": converting NULL to int is unsupported" {
			/* user doesn't have key attributes, deleting the srp auth entry,
			   so that the user can setup srp again fresh along with key attributes
			   Can happen if the key attributes setup API is fails, but the srp setup API succeeds
			   TODO: create a single API for both key attributes and srp setup
			*/
			_, err := repo.DB.Exec(`DELETE FROM srp_auth WHERE user_id = $1`, userID)
			if err != nil {
				return nil, stacktrace.Propagate(err, "")
			}
			log.WithField("user_id", userID).Warn("deleted srp auth missing key attributes")
			return nil, stacktrace.Propagate(&ente.ErrNotFoundError, "key attributes are not present")
		}
		return nil, stacktrace.Propagate(err, "failed to read srp attributes")
	}
	return &srpAttributes, stacktrace.Propagate(err, "")
}
