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

// AddSRPSession inserts a SRPSession and returns the session id
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

// IsSRPSetupDone returns true if the user has already set SRP attributes
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

// UpdateEmailMFA updates the email MFA status of a user
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

// InsertTempSRPSetup inserts an entry into the temp_srp_setup table. It also returns the ID of the inserted row
func (repo *UserAuthRepository) InsertTempSRPSetup(ctx context.Context, req ente.SetupSRPRequest, userID int64, sessionID *uuid.UUID) (*uuid.UUID, error) {
	id := uuid.New()
	_, err := repo.DB.ExecContext(ctx, `
	INSERT INTO temp_srp_setup(id, session_id, user_id, srp_user_id, salt, verifier) VALUES($1, $2 , $3, $4, $5, $6)`,
		id, sessionID, userID, req.SrpUserID, req.SRPSalt, req.SRPVerifier)
	return &id, stacktrace.Propagate(err, "")
}

func (repo *UserAuthRepository) GetTempSRPSetupEntity(ctx context.Context, setUpID uuid.UUID) (*ente.SRPSetupEntity, error) {
	result := ente.SRPSetupEntity{}
	row := repo.DB.QueryRowContext(ctx, `SELECT id, session_id, user_id, srp_user_id, salt, verifier FROM temp_srp_setup WHERE id = $1`, setUpID)
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

func (repo *UserAuthRepository) InsertOrUpdateSRPAuthAndKeyAttr(ctx context.Context, userID int64, req ente.UpdateSRPAndKeysRequest, setup *ente.SRPSetupEntity) error {
	isSRPSetupDone, err := repo.IsSRPSetupDone(ctx, userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if !isSRPSetupDone {
		_, err = tx.ExecContext(ctx, `
	INSERT INTO srp_auth(user_id, srp_user_id, salt, verifier) VALUES($1, $2 , $3, $4)`,
			userID, setup.SRPUserID, setup.Salt, setup.Verifier)
	} else {
		_, err = tx.ExecContext(ctx, `UPDATE srp_auth SET srp_user_id = $1, salt = $2, verifier = $3 WHERE user_id = $4`,
			setup.SRPUserID, setup.Salt, setup.Verifier, userID)
	}
	if err != nil {
		rollBackErr := tx.Rollback()
		if rollBackErr != nil {
			return rollBackErr
		}
		return stacktrace.Propagate(err, "")
	}
	updateKeyAttr := *req.UpdateAttributes
	if validErr := updateKeyAttr.Validate(); validErr != nil {
		return stacktrace.Propagate(validErr, "")
	}
	_, err = tx.ExecContext(ctx, `UPDATE key_attributes SET kek_salt = $1, encrypted_key = $2, key_decryption_nonce = $3, mem_limit = $4, ops_limit = $5 WHERE user_id = $6`,
		updateKeyAttr.KEKSalt, updateKeyAttr.EncryptedKey, updateKeyAttr.KeyDecryptionNonce, updateKeyAttr.MemLimit, updateKeyAttr.OpsLimit, userID)
	if err != nil {
		rollBackErr := tx.Rollback()
		if rollBackErr != nil {
			return rollBackErr
		}
		return stacktrace.Propagate(err, "")
	}
	return tx.Commit()
}

// GetSrpSessionEntity ...
func (repo *UserAuthRepository) GetSrpSessionEntity(ctx context.Context, sessionID uuid.UUID) (*ente.SRPSessionEntity, error) {
	result := ente.SRPSessionEntity{}
	row := repo.DB.QueryRowContext(ctx, `SELECT id, srp_user_id, server_key, srp_a, has_verified, attempt_count, COALESCE(is_fake, false) FROM srp_sessions WHERE id = $1`, sessionID)
	err := row.Scan(&result.ID, &result.SRPUserID, &result.ServerKey, &result.SRP_A, &result.IsVerified, &result.AttemptCount, &result.IsFake)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &result, nil
}

// IncrementSrpSessionAttemptCount increments the verification attempt count of a session
func (repo *UserAuthRepository) IncrementSrpSessionAttemptCount(ctx context.Context, sessionID uuid.UUID) error {
	_, err := repo.DB.ExecContext(ctx, `UPDATE srp_sessions SET attempt_count = attempt_count + 1 WHERE id = $1`, sessionID)
	return stacktrace.Propagate(err, "")
}

// SetSrpSessionVerified ..
func (repo *UserAuthRepository) SetSrpSessionVerified(ctx context.Context, sessionID uuid.UUID) error {
	_, err := repo.DB.ExecContext(ctx, `UPDATE srp_sessions SET has_verified = true WHERE id = $1`, sessionID)
	return stacktrace.Propagate(err, "")
}

// CleanupOldFakeSessions removes fake sessions older than the specified duration
func (repo *UserAuthRepository) CleanupOldFakeSessions(ctx context.Context) (int64, error) {
	// Delete fake sessions older than specified microseconds
	result, err := repo.DB.ExecContext(ctx, `
		DELETE FROM srp_sessions
		WHERE is_fake = true
		AND created_at < (now_utc_micro_seconds() - (24::BIGINT * 60 * 60 * 1000 * 1000))`)
	if err != nil {
		return 0, stacktrace.Propagate(err, "failed to cleanup old fake sessions")
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return 0, stacktrace.Propagate(err, "failed to get rows affected")
	}
	return rowsAffected, nil
}

// GetSRPAttributes returns the srp attributes of a user
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
