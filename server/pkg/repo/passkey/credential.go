package passkey

import (
	"time"

	"github.com/ente/museum/ente"
	"github.com/google/uuid"
)

func (r *Repository) createPasskey(userID int64, friendlyName string) (newPasskey *ente.Passkey, err error) {

	newPasskey = &ente.Passkey{
		ID:           uuid.New(),
		UserID:       userID,
		FriendlyName: friendlyName,
		CreatedAt:    time.Now().UnixMicro(),
	}

	_, err = r.DB.Exec(`
		INSERT INTO passkeys (
			id,
			user_id,
			friendly_name,
			created_at
		) VALUES (
			$1,
			$2,
			$3,
			$4
		)
		`,
		newPasskey.ID,
		newPasskey.UserID,
		newPasskey.FriendlyName,
		newPasskey.CreatedAt,
	)

	return
}

func (r *Repository) createPasskeyCredential(credential *ente.PasskeyCredential) (err error) {
	_, err = r.DB.Exec(`
		INSERT INTO passkey_credentials(
			passkey_id,
			rp_id,
			public_key,
			attestation_type,
			authenticator_transports,
			credential_flags,
			authenticator,
			created_at,
			credential_id
		) VALUES (
			$1,
			$2,
			$3,
			$4,
			$5,
			$6,
			$7,
			$8,
			$9
		)`,
		credential.PasskeyID,
		credential.RPID,
		credential.PublicKey,
		credential.AttestationType,
		credential.AuthenticatorTransports,
		credential.CredentialFlags,
		credential.Authenticator,
		credential.CreatedAt,
		credential.CredentialID,
	)
	if err != nil {
		return
	}

	return
}
