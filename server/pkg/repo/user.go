package repo

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/ente/museum/pkg/repo/passkey"
	storageBonusRepo "github.com/ente/museum/pkg/repo/storagebonus"
	emailUtil "github.com/ente/museum/pkg/utils/email"
	"github.com/ente/stacktrace"
	"github.com/lib/pq"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/crypto"
	"github.com/ente/museum/pkg/utils/time"
)

const (
	// Format for updated email_hash once the account is deleted
	DELETED_EMAIL_HASH_FORMAT = "deleted+%d@ente.io"
)

// UserRepository defines the methods for inserting, updating and retrieving
// user entities from the underlying repository
type UserRepository struct {
	DB                  *sql.DB
	SecretEncryptionKey []byte
	HashingKey          []byte
	StorageBonusRepo    *storageBonusRepo.Repository
	PasskeysRepository  *passkey.Repository
}

// UserInactivityCandidate captures the latest known activity timestamp for an
// active (non-deleted) user account.
type UserInactivityCandidate struct {
	UserID       int64
	LastActivity int64
}

type userMutationExecutor interface {
	ExecContext(context.Context, string, ...any) (sql.Result, error)
}

// Get returns a user indicated by the userID
func (repo *UserRepository) Get(userID int64) (ente.User, error) {
	var user ente.User
	var encryptedEmail, nonce []byte
	row := repo.DB.QueryRow(`SELECT user_id, encrypted_email, email_decryption_nonce, email_hash, family_admin_id, creation_time, is_two_factor_enabled, email_mfa FROM users WHERE user_id = $1`, userID)
	err := row.Scan(&user.ID, &encryptedEmail, &nonce, &user.Hash, &user.FamilyAdminID, &user.CreationTime, &user.IsTwoFactorEnabled, &user.IsEmailMFAEnabled)
	if err != nil {
		return ente.User{}, stacktrace.Propagate(err, "")
	}
	// We should not be calling Get user for a deleted account. The one valid
	// use case is for internal/Admin APIs, where please we should instead be
	// using GetUserByIDInternal.
	if strings.EqualFold(user.Hash, fmt.Sprintf(DELETED_EMAIL_HASH_FORMAT, userID)) {
		return user, stacktrace.Propagate(ente.ErrUserDeleted, "user account is deleted %d", userID)
	}
	email, err := crypto.Decrypt(encryptedEmail, repo.SecretEncryptionKey, nonce)
	if err != nil {
		return ente.User{}, stacktrace.Propagate(err, "")
	}
	user.Email = email
	return user, nil
}

// GetUserByIDInternal returns a user indicated by the id. Strickly use this method for internal APIs only.
func (repo *UserRepository) GetUserByIDInternal(id int64) (ente.User, error) {
	var user ente.User
	var encryptedEmail, nonce []byte
	row := repo.DB.QueryRow(`SELECT user_id, encrypted_email, email_decryption_nonce, email_hash, family_admin_id, creation_time FROM users WHERE user_id = $1 AND encrypted_email IS NOT NULL`, id)
	err := row.Scan(&user.ID, &encryptedEmail, &nonce, &user.Hash, &user.FamilyAdminID, &user.CreationTime)
	if err != nil {
		return ente.User{}, stacktrace.Propagate(err, "")
	}
	email, err := crypto.Decrypt(encryptedEmail, repo.SecretEncryptionKey, nonce)
	if err != nil {
		return ente.User{}, stacktrace.Propagate(err, "")
	}
	user.Email = email
	return user, nil
}

// Return true if userId 1 doesn't exists in the system.
func (repo *UserRepository) IsLikelySelfHosted() bool {
	var userOneExists bool
	if err := repo.DB.QueryRow(`SELECT EXISTS(SELECT 1 FROM users WHERE user_id = 1)`).Scan(&userOneExists); err != nil {
		return false
	}

	return !userOneExists
}

// Delete removes the email_hash and encrypted email information for the user. It replaces email_hash with placeholder value
// based on DELETED_EMAIL_HASH_FORMAT
func (repo *UserRepository) Delete(userID int64) error {
	return deleteUser(context.Background(), repo.DB, userID)
}

func (repo *UserRepository) DeleteTx(ctx context.Context, tx *sql.Tx, userID int64) (string, error) {
	var emailHash string
	if err := tx.QueryRowContext(ctx, `SELECT email_hash FROM users WHERE user_id = $1 FOR UPDATE`, userID).Scan(&emailHash); err != nil {
		return "", stacktrace.Propagate(err, "failed to read email hash")
	}
	return emailHash, deleteUser(ctx, tx, userID)
}

func deleteUser(ctx context.Context, executor userMutationExecutor, userID int64) error {
	deletedEmailHash := fmt.Sprintf(DELETED_EMAIL_HASH_FORMAT, userID)
	_, err := executor.ExecContext(ctx, `UPDATE users SET encrypted_email = null, email_decryption_nonce = null, email_hash = $1 WHERE user_id = $2`, deletedEmailHash, userID)
	return stacktrace.Propagate(err, "")
}

// GetFamilyAdminID returns the *familyAdminID for the given userID
func (repo *UserRepository) GetFamilyAdminID(userID int64) (*int64, error) {
	row := repo.DB.QueryRow(`SELECT family_admin_id FROM users WHERE user_id = $1`, userID)
	var familyAdminID *int64
	err := row.Scan(&familyAdminID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return familyAdminID, nil
}

// GetUserByEmailHash returns a user indicated by the emailHash
func (repo *UserRepository) GetUserByEmailHash(emailHash string) (ente.User, error) {
	var user ente.User
	row := repo.DB.QueryRow(`SELECT user_id, email_hash, creation_time FROM users WHERE email_hash = $1`, emailHash)
	err := row.Scan(&user.ID, &user.Hash, &user.CreationTime)
	if err != nil {
		return ente.User{}, stacktrace.Propagate(err, "")
	}
	return user, nil
}

// GetAll returns all users between sinceTime and tillTime (exclusive).
func (repo *UserRepository) GetAll(sinceTime int64, tillTime int64) ([]ente.User, error) {
	rows, err := repo.DB.Query(`SELECT user_id, encrypted_email, email_decryption_nonce, email_hash, creation_time FROM users WHERE creation_time > $1 AND creation_time < $2 AND encrypted_email IS NOT NULL ORDER BY creation_time`, sinceTime, tillTime)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	users := make([]ente.User, 0)
	for rows.Next() {
		var user ente.User
		var encryptedEmail, nonce []byte
		err := rows.Scan(&user.ID, &encryptedEmail, &nonce, &user.Hash, &user.CreationTime)

		if err != nil {
			return users, stacktrace.Propagate(err, "")
		}
		email, err := crypto.Decrypt(encryptedEmail, repo.SecretEncryptionKey, nonce)
		if err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		user.Email = email
		users = append(users, user)
	}
	return users, nil
}

// GetActiveUsersByLastActivityBefore returns active users whose effective last
// activity is older than or equal to beforeTime. Effective activity uses latest
// token activity when present, otherwise falls back to max(users.creation_time,
// authenticator_entity.updated_at, collections.updation_time). Paging is done
// by user_id.
func (repo *UserRepository) GetActiveUsersByLastActivityBefore(beforeTime int64, afterUserID int64, limit int) ([]UserInactivityCandidate, error) {
	rows, err := repo.DB.Query(`
		SELECT
			candidate.user_id,
			candidate.last_activity
		FROM (
			SELECT
				u.user_id,
				COALESCE(
					t.last_token_activity,
					GREATEST(
						u.creation_time,
						COALESCE(a.last_auth_activity, 0),
						COALESCE(c.last_collection_activity, 0)
					)
				) AS last_activity
			FROM users u
			LEFT JOIN LATERAL (
				SELECT t.last_used_at AS last_token_activity
				FROM tokens t
				WHERE t.user_id = u.user_id
				ORDER BY t.last_used_at DESC
				LIMIT 1
			) t ON TRUE
			LEFT JOIN LATERAL (
				SELECT ae.updated_at AS last_auth_activity
				FROM authenticator_entity ae
				WHERE ae.user_id = u.user_id
				ORDER BY ae.updated_at DESC
				LIMIT 1
			) a ON TRUE
			LEFT JOIN LATERAL (
				SELECT c.updation_time AS last_collection_activity
				FROM collections c
				WHERE c.owner_id = u.user_id
				ORDER BY c.updation_time DESC
				LIMIT 1
				) c ON TRUE
				WHERE u.encrypted_email IS NOT NULL
					AND u.creation_time <= $1
					AND u.user_id > $2
			) candidate
			WHERE candidate.last_activity <= $1
		ORDER BY candidate.user_id
		LIMIT $3`, beforeTime, afterUserID, limit)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to fetch inactive users")
	}
	defer rows.Close()

	result := make([]UserInactivityCandidate, 0)
	for rows.Next() {
		var candidate UserInactivityCandidate
		if err := rows.Scan(&candidate.UserID, &candidate.LastActivity); err != nil {
			return nil, stacktrace.Propagate(err, "failed to scan inactive user row")
		}
		result = append(result, candidate)
	}
	if err := rows.Err(); err != nil {
		return nil, stacktrace.Propagate(err, "failed to iterate inactive users")
	}
	return result, nil
}

// GetLatestActivity returns the latest effective activity for a user.
// The second return value is false when the user is no longer active.
func (repo *UserRepository) GetLatestActivity(userID int64) (int64, bool, error) {
	var lastActivity int64
	err := repo.DB.QueryRow(`
		SELECT
			COALESCE(
				t.last_token_activity,
				GREATEST(
					u.creation_time,
					COALESCE(a.last_auth_activity, 0),
					COALESCE(c.last_collection_activity, 0)
				)
			) AS last_activity
		FROM users u
		LEFT JOIN LATERAL (
			SELECT t.last_used_at AS last_token_activity
			FROM tokens t
			WHERE t.user_id = u.user_id
			ORDER BY t.last_used_at DESC
			LIMIT 1
		) t ON TRUE
		LEFT JOIN LATERAL (
			SELECT ae.updated_at AS last_auth_activity
			FROM authenticator_entity ae
			WHERE ae.user_id = u.user_id
			ORDER BY ae.updated_at DESC
			LIMIT 1
		) a ON TRUE
		LEFT JOIN LATERAL (
			SELECT c.updation_time AS last_collection_activity
			FROM collections c
			WHERE c.owner_id = u.user_id
			ORDER BY c.updation_time DESC
			LIMIT 1
		) c ON TRUE
		WHERE u.user_id = $1
			AND u.encrypted_email IS NOT NULL
	`, userID).Scan(&lastActivity)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return 0, false, nil
		}
		return 0, false, stacktrace.Propagate(err, "failed to fetch latest user activity")
	}
	return lastActivity, true, nil
}

// GetUserUsageWithSubData will return current storage usage & basic information about subscription for given list
// of users. It's primarily used for fetching storage utilisation for a family/group of users
func (repo *UserRepository) GetUserUsageWithSubData(ctx context.Context, userIds []int64) ([]ente.UserUsageWithSubData, error) {
	rows, err := repo.DB.QueryContext(ctx, `select encrypted_email, email_decryption_nonce, u.user_id, coalesce(storage_consumed , 0) as storage_used, storage, expiry_time 
	from users as u
	left join (select storage_consumed, user_id from usage where user_id = ANY($1)) as us 
	    on us.user_id=u.user_id
	left join (select user_id,expiry_time, storage from subscriptions where user_id = ANY($1)) as s 
	    on s.user_id = u.user_id
			where u.user_id = ANY($1)`, pq.Array(userIds))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	result := make([]ente.UserUsageWithSubData, 0)
	for rows.Next() {
		var (
			usageData             ente.UserUsageWithSubData
			encryptedEmail, nonce []byte
		)
		err = rows.Scan(&encryptedEmail, &nonce, &usageData.UserID, &usageData.StorageConsumed, &usageData.Storage, &usageData.ExpiryTime)
		if err != nil {
			return result, stacktrace.Propagate(err, "")
		}
		email, err := crypto.Decrypt(encryptedEmail, repo.SecretEncryptionKey, nonce)
		if err != nil {
			return nil, stacktrace.Propagate(err, "failed to decrypt email")
		}
		usageData.Email = &email
		result = append(result, usageData)
	}
	return result, nil
}

// Create creates a user with a given email address and returns the generated
// userID
func (repo *UserRepository) Create(encryptedEmail ente.EncryptionResult, emailHash string, source *string) (int64, error) {
	var userID int64
	err := repo.DB.QueryRow(`INSERT INTO users(encrypted_email, email_decryption_nonce, email_hash, creation_time, source) VALUES($1, $2, $3, $4, $5) RETURNING user_id`,
		encryptedEmail.Cipher, encryptedEmail.Nonce, emailHash, time.Microseconds(), source).Scan(&userID)
	if err != nil {
		return -1, stacktrace.Propagate(err, "")
	}
	return userID, nil
}

// UpdateDeleteFeedback for a given user in the delete_feedback column of type jsonb
func (repo *UserRepository) UpdateDeleteFeedback(userID int64, feedback map[string]string) error {
	// Convert the feedback map into JSON
	feedbackJSON, err := json.Marshal(feedback)
	if err != nil {
		return stacktrace.Propagate(err, "Failed to marshal feedback into JSON")
	}
	// Execute the update query with the JSON
	_, err = repo.DB.Exec(`UPDATE users SET delete_feedback = $1 WHERE user_id = $2`, feedbackJSON, userID)
	return stacktrace.Propagate(err, "Failed to update delete feedback")
}

// UpdateEmail updates the email address of a user
func (repo *UserRepository) UpdateEmail(userID int64, encryptedEmail ente.EncryptionResult, emailHash string) error {
	return updateEmail(context.Background(), repo.DB, userID, encryptedEmail, emailHash)
}

func (repo *UserRepository) UpdateEmailTx(ctx context.Context, tx *sql.Tx, userID int64, encryptedEmail ente.EncryptionResult, emailHash string) error {
	return updateEmail(ctx, tx, userID, encryptedEmail, emailHash)
}

func updateEmail(ctx context.Context, executor userMutationExecutor, userID int64, encryptedEmail ente.EncryptionResult, emailHash string) error {
	_, err := executor.ExecContext(ctx, `UPDATE users SET encrypted_email = $1, email_decryption_nonce = $2, email_hash = $3 WHERE user_id = $4`, encryptedEmail.Cipher, encryptedEmail.Nonce, emailHash, userID)
	return stacktrace.Propagate(err, "")
}

// GetUserIDWithEmailUnrestricted returns the user ID associated with an email.
// It bypasses authenticated discovery limits and is only for trusted,
// non-disclosing flows. User-facing discovery must use controller.UserLookup.
func (repo *UserRepository) GetUserIDWithEmailUnrestricted(email string) (int64, error) {
	sanitizedEmail := emailUtil.NormalizeEmail(email)
	emailHash, err := crypto.GetHash(sanitizedEmail, repo.HashingKey)
	if err != nil {
		return -1, stacktrace.Propagate(err, "")
	}
	row := repo.DB.QueryRow(`SELECT user_id FROM users WHERE email_hash = $1`, emailHash)
	var userID int64
	err = row.Scan(&userID)
	if err != nil {
		return -1, stacktrace.Propagate(err, "")
	}
	return userID, nil
}

// GetKeyAttributes gets the key attributes for a given user
func (repo *UserRepository) GetKeyAttributes(userID int64) (ente.KeyAttributes, error) {
	row := repo.DB.QueryRow(`SELECT kek_salt, kek_hash_bytes, encrypted_key, key_decryption_nonce, public_key, encrypted_secret_key, secret_key_decryption_nonce, mem_limit, ops_limit, master_key_encrypted_with_recovery_key, master_key_decryption_nonce, recovery_key_encrypted_with_master_key, recovery_key_decryption_nonce FROM key_attributes WHERE user_id = $1`, userID)
	var (
		keyAttributes                     ente.KeyAttributes
		kekHashBytes                      []byte
		masterKeyEncryptedWithRecoveryKey sql.NullString
		masterKeyDecryptionNonce          sql.NullString
		recoveryKeyEncryptedWithMasterKey sql.NullString
		recoveryKeyDecryptionNonce        sql.NullString
	)
	err := row.Scan(&keyAttributes.KEKSalt,
		&kekHashBytes,
		&keyAttributes.EncryptedKey,
		&keyAttributes.KeyDecryptionNonce,
		&keyAttributes.PublicKey,
		&keyAttributes.EncryptedSecretKey,
		&keyAttributes.SecretKeyDecryptionNonce,
		&keyAttributes.MemLimit,
		&keyAttributes.OpsLimit,
		&masterKeyEncryptedWithRecoveryKey,
		&masterKeyDecryptionNonce,
		&recoveryKeyEncryptedWithMasterKey,
		&recoveryKeyDecryptionNonce,
	)
	if err != nil {
		return ente.KeyAttributes{}, stacktrace.Propagate(err, "")
	}
	keyAttributes.KEKHash = string(kekHashBytes)
	if masterKeyEncryptedWithRecoveryKey.Valid {
		keyAttributes.MasterKeyEncryptedWithRecoveryKey = masterKeyEncryptedWithRecoveryKey.String
	}
	if masterKeyDecryptionNonce.Valid {
		keyAttributes.MasterKeyDecryptionNonce = masterKeyDecryptionNonce.String
	}
	if recoveryKeyEncryptedWithMasterKey.Valid {
		keyAttributes.RecoveryKeyEncryptedWithMasterKey = recoveryKeyEncryptedWithMasterKey.String
	}
	if recoveryKeyDecryptionNonce.Valid {
		keyAttributes.RecoveryKeyDecryptionNonce = recoveryKeyDecryptionNonce.String
	}

	return keyAttributes, nil
}

// SetKeyAttributes sets the key attributes for a given user
func (repo *UserRepository) SetKeyAttributes(userID int64, keyAttributes ente.KeyAttributes) error {
	_, err := repo.DB.Exec(`INSERT INTO key_attributes(user_id, kek_salt, kek_hash_bytes, encrypted_key, key_decryption_nonce, public_key, encrypted_secret_key, secret_key_decryption_nonce, mem_limit, ops_limit, master_key_encrypted_with_recovery_key, master_key_decryption_nonce, recovery_key_encrypted_with_master_key, recovery_key_decryption_nonce) VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)`,
		userID, keyAttributes.KEKSalt, []byte(keyAttributes.KEKHash),
		keyAttributes.EncryptedKey, keyAttributes.KeyDecryptionNonce,
		keyAttributes.PublicKey, keyAttributes.EncryptedSecretKey,
		keyAttributes.SecretKeyDecryptionNonce, keyAttributes.MemLimit, keyAttributes.OpsLimit,
		keyAttributes.MasterKeyEncryptedWithRecoveryKey, keyAttributes.MasterKeyDecryptionNonce,
		keyAttributes.RecoveryKeyEncryptedWithMasterKey, keyAttributes.RecoveryKeyDecryptionNonce)
	return stacktrace.Propagate(err, "")
}

// SetRecoveryKeyAttributes sets the recovery key and related attributes for a user
func (repo *UserRepository) SetRecoveryKeyAttributes(userID int64, keys ente.SetRecoveryKeyRequest) error {
	_, err := repo.DB.Exec(`UPDATE key_attributes SET master_key_encrypted_with_recovery_key = $1, master_key_decryption_nonce = $2, recovery_key_encrypted_with_master_key = $3, recovery_key_decryption_nonce = $4 WHERE user_id = $5`,
		keys.MasterKeyEncryptedWithRecoveryKey, keys.MasterKeyDecryptionNonce, keys.RecoveryKeyEncryptedWithMasterKey, keys.RecoveryKeyDecryptionNonce, userID)
	return stacktrace.Propagate(err, "")
}

// GetPublicKey returns the public key of a user
func (repo *UserRepository) GetPublicKey(userID int64) (string, error) {
	row := repo.DB.QueryRow(`SELECT public_key FROM key_attributes WHERE user_id = $1`, userID)
	var publicKey string
	err := row.Scan(&publicKey)
	return publicKey, stacktrace.Propagate(err, "")
}

// GetUsersWithIndividualPlanWhoHaveExceededStorageQuota returns list of users who have consumed their storage quota
// and they are not part of any family plan
func (repo *UserRepository) GetUsersWithIndividualPlanWhoHaveExceededStorageQuota() ([]ente.User, error) {
	rows, err := repo.DB.Query(`
		SELECT users.user_id, users.encrypted_email, users.email_decryption_nonce, users.email_hash, usage.storage_consumed, subscriptions.storage
		FROM users 
		INNER JOIN usage 
		ON users.user_id = usage.user_id 
		INNER JOIN subscriptions 
		ON users.user_id = subscriptions.user_id AND usage.storage_consumed > subscriptions.storage AND users.encrypted_email IS NOT NULL AND users.family_admin_id IS NULL;
	`)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	refBonus, addOnBonus, bonusErr := repo.StorageBonusRepo.GetAllUsersSurplusBonus(context.Background())
	if bonusErr != nil {
		return nil, stacktrace.Propagate(bonusErr, "failed to fetch bonusInfo")
	}
	defer rows.Close()
	users := make([]ente.User, 0)
	for rows.Next() {
		var user ente.User
		var encryptedEmail, nonce []byte
		var storageConsumed, subStorage int64
		err := rows.Scan(&user.ID, &encryptedEmail, &nonce, &user.Hash, &storageConsumed, &subStorage)
		if err != nil {
			return users, stacktrace.Propagate(err, "")
		}
		// ignore deleted users
		if strings.EqualFold(user.Hash, fmt.Sprintf(DELETED_EMAIL_HASH_FORMAT, &user.ID)) || len(encryptedEmail) == 0 {
			continue
		}
		if refBonusStorage, ok := refBonus[user.ID]; ok {
			addOnBonusStorage := addOnBonus[user.ID]
			// cap usable ref bonus to the subscription storage + addOnBonus
			if refBonusStorage > (subStorage + addOnBonusStorage) {
				refBonusStorage = subStorage + addOnBonusStorage
			}
			if (storageConsumed) <= (subStorage + refBonusStorage + addOnBonusStorage) {
				continue
			}
		}
		email, err := crypto.Decrypt(encryptedEmail, repo.SecretEncryptionKey, nonce)
		if err != nil {
			return users, stacktrace.Propagate(err, "")
		}
		user.Email = email
		users = append(users, user)
	}
	return users, nil
}

func (repo *UserRepository) GetUsersWhoUpgradedNDaysAgo(days int) ([]ente.User, error) {
	rows, err := repo.DB.Query(`
        SELECT u.user_id, u.encrypted_email, u.email_decryption_nonce, u.email_hash, u.creation_time 
        FROM users u
        INNER JOIN subscriptions s ON u.user_id = s.user_id
        WHERE s.upgraded_at >= $1 AND s.upgraded_at < $2 AND u.encrypted_email IS NOT NULL`,
		time.MicrosecondsBeforeDays(days+1), time.MicrosecondsBeforeDays(days))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	users := make([]ente.User, 0)
	for rows.Next() {
		var user ente.User
		var encryptedEmail, nonce []byte
		err := rows.Scan(&user.ID, &encryptedEmail, &nonce, &user.Hash, &user.CreationTime)
		if err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		email, err := crypto.Decrypt(encryptedEmail, repo.SecretEncryptionKey, nonce)
		if err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		user.Email = email
		users = append(users, user)
	}
	return users, nil
}

// SetTwoFactorSecret sets the two factor secret for a user
func (repo *UserRepository) SetTwoFactorSecret(userID int64, secret ente.EncryptionResult, secretHash string, recoveryEncryptedTwoFactorSecret string, recoveryTwoFactorSecretDecryptionNonce string) error {
	_, err := repo.DB.Exec(`INSERT INTO two_factor(user_id,encrypted_two_factor_secret,two_factor_secret_decryption_nonce,two_factor_secret_hash,recovery_encrypted_two_factor_secret,recovery_two_factor_secret_decryption_nonce) 
		VALUES($1, $2, $3, $4, $5, $6) 
		ON CONFLICT (user_id) DO UPDATE
			SET encrypted_two_factor_secret = $2,
				two_factor_secret_decryption_nonce = $3,
				two_factor_secret_hash = $4,
				recovery_encrypted_two_factor_secret = $5,
				recovery_two_factor_secret_decryption_nonce = $6
				`,
		userID, secret.Cipher, secret.Nonce, secretHash, recoveryEncryptedTwoFactorSecret, recoveryTwoFactorSecretDecryptionNonce)
	return stacktrace.Propagate(err, "")
}

// IsTwoFactorEnabled checks if a user's two factor is enabled or not
func (repo *UserRepository) IsTwoFactorEnabled(userID int64) (bool, error) {
	var twoFAStatus bool
	row := repo.DB.QueryRow(`SELECT is_two_factor_enabled FROM users WHERE user_id = $1`, userID)
	err := row.Scan(&twoFAStatus)
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	return twoFAStatus, nil
}

func (repo *UserRepository) HasPasskeys(userID int64) (hasPasskeys bool, err error) {
	passkeys, err := repo.PasskeysRepository.GetUserPasskeys(userID)
	hasPasskeys = len(passkeys) > 0
	return
}

func (repo *UserRepository) GetEmailsFromHashes(hashes []string) ([]string, error) {
	rows, err := repo.DB.Query(`
		SELECT users.encrypted_email, users.email_decryption_nonce 
		FROM users 
		WHERE users.email_hash = ANY($1);
	`, pq.Array(hashes))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	emails := make([]string, 0)
	for rows.Next() {
		var encryptedEmail, nonce []byte
		err := rows.Scan(&encryptedEmail, &nonce)
		if err != nil {
			return emails, stacktrace.Propagate(err, "")
		}
		email, err := crypto.Decrypt(encryptedEmail, repo.SecretEncryptionKey, nonce)
		if err != nil {
			return emails, stacktrace.Propagate(err, "")
		}
		emails = append(emails, email)
	}
	return emails, nil
}

// CountActiveUsersByEmailHashes returns count of active users matching any of
// the provided hashes.
func (repo *UserRepository) CountActiveUsersByEmailHashes(hashes []string) (int, error) {
	if len(hashes) == 0 {
		return 0, nil
	}
	var count int
	err := repo.DB.QueryRow(`
		SELECT COUNT(*)
		FROM users
		WHERE encrypted_email IS NOT NULL
		  AND email_hash = ANY($1);
	`, pq.Array(hashes)).Scan(&count)
	if err != nil {
		return 0, stacktrace.Propagate(err, "")
	}
	return count, nil
}

// GetActiveUserEmailHashes returns active user email hashes present in the
// provided list of hashes.
func (repo *UserRepository) GetActiveUserEmailHashes(hashes []string) ([]string, error) {
	if len(hashes) == 0 {
		return []string{}, nil
	}
	rows, err := repo.DB.Query(`
		SELECT email_hash
		FROM users
		WHERE encrypted_email IS NOT NULL
		  AND email_hash = ANY($1);
	`, pq.Array(hashes))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()

	matchedHashes := make([]string, 0, len(hashes))
	for rows.Next() {
		var emailHash string
		if err := rows.Scan(&emailHash); err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		matchedHashes = append(matchedHashes, emailHash)
	}
	if err := rows.Err(); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return matchedHashes, nil
}

// GetActiveUsersForIds  returns a map of users by their IDs, similar to GetUserByID
func (repo *UserRepository) GetActiveUsersForIds(id []int64) (map[int64]*ente.User, error) {
	result := make(map[int64]*ente.User)
	rows, err := repo.DB.Query(`SELECT user_id, encrypted_email, email_decryption_nonce, email_hash, creation_time FROM users WHERE  encrypted_email IS NOT NULL and user_id = ANY($1)`, pq.Array(id))
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	defer rows.Close()
	for rows.Next() {
		var user ente.User
		var encryptedEmail, nonce []byte
		err := rows.Scan(&user.ID, &encryptedEmail, &nonce, &user.Hash, &user.CreationTime)
		if err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		email, err := crypto.Decrypt(encryptedEmail, repo.SecretEncryptionKey, nonce)
		if err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		user.Email = email
		result[user.ID] = &user
	}
	return result, nil

}
