package two_factor_recovery

import (
	"context"
	"crypto/subtle"
	"database/sql"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/crypto"
	"github.com/ente/stacktrace"
	"github.com/sirupsen/logrus"
)

type Repository struct {
	Db                  *sql.DB
	SecretEncryptionKey []byte
}

// GetStatus returns `ente.TwoFactorRecoveryStatus` for a user
func (r *Repository) GetStatus(userID int64) (*ente.TwoFactorRecoveryStatus, error) {
	var isAdminResetEnabled bool
	var resetKey []byte
	row := r.Db.QueryRow(`SELECT enable_admin_mfa_reset, server_passkey_secret_data FROM two_factor_recovery WHERE user_id = $1`, userID)
	err := row.Scan(&isAdminResetEnabled, &resetKey)
	if err != nil {
		if err == sql.ErrNoRows {
			// by default, admin
			return &ente.TwoFactorRecoveryStatus{
				AllowAdminReset:          true,
				IsPasskeyRecoveryEnabled: false,
			}, nil
		}
		return nil, err
	}
	return &ente.TwoFactorRecoveryStatus{AllowAdminReset: isAdminResetEnabled, IsPasskeyRecoveryEnabled: len(resetKey) > 0}, nil
}

func (r *Repository) SetPasskeyRecovery(ctx context.Context, userID int64, req *ente.SetPasskeyRecoveryRequest) error {
	serveEncPasskey, encErr := crypto.Encrypt(req.Secret, r.SecretEncryptionKey)
	if encErr != nil {
		return stacktrace.Propagate(encErr, "failed to encrypt passkey secret")
	}
	_, err := r.Db.ExecContext(ctx, `INSERT INTO two_factor_recovery 
    (user_id, server_passkey_secret_data, server_passkey_secret_nonce, user_passkey_secret_data, user_passkey_secret_nonce) 
	VALUES ($1, $2, $3, $4, $5)  ON CONFLICT (user_id) 
	DO UPDATE SET server_passkey_secret_data = $2, server_passkey_secret_nonce = $3, user_passkey_secret_data = $4, user_passkey_secret_nonce = $5 
	WHERE two_factor_recovery.user_passkey_secret_data IS NULL AND two_factor_recovery.server_passkey_secret_data IS NULL`,
		userID, serveEncPasskey.Cipher, serveEncPasskey.Nonce, req.UserSecretCipher, req.UserSecretNonce)
	return err
}

func (r *Repository) GetPasskeyRecoveryData(ctx context.Context, userID int64) (*ente.TwoFactorRecoveryResponse, error) {
	var result ente.TwoFactorRecoveryResponse
	err := r.Db.QueryRowContext(ctx, "SELECT user_passkey_secret_data, user_passkey_secret_nonce FROM two_factor_recovery WHERE  user_id= $1", userID).Scan(&result.EncryptedSecret, &result.SecretDecryptionNonce)
	if err != nil {
		return nil, err
	}
	return &result, nil
}

// ValidatePasskeyRecoverySecret checks if the passkey skip secret is valid for a user
func (r *Repository) ValidatePasskeyRecoverySecret(userID int64, secret string) (bool, error) {
	// get server_passkey_secret_data and server_passkey_secret_nonce for given user id
	var severSecreteData, serverSecretNonce []byte
	row := r.Db.QueryRow(`SELECT server_passkey_secret_data, server_passkey_secret_nonce FROM two_factor_recovery WHERE user_id = $1`, userID)
	err := row.Scan(&severSecreteData, &serverSecretNonce)
	if err != nil {
		return false, stacktrace.Propagate(err, "")
	}
	// decrypt server_passkey_secret_data
	serverSkipSecretKey, decErr := crypto.Decrypt(severSecreteData, r.SecretEncryptionKey, serverSecretNonce)
	// serverSkipSecretKey, decErr := crypto.Decrypt(severSecreteData,serverSecretNonce, r.SecretEncryptionKey )
	if decErr != nil {
		return false, stacktrace.Propagate(decErr, "failed to decrypt passkey reset key")
	}
	if subtle.ConstantTimeCompare([]byte(secret), []byte(serverSkipSecretKey)) != 1 {
		logrus.Warn("invalid passkey skip secret")
		return false, nil
	}
	return true, nil
}
