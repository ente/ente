package passkey

import "github.com/ente/museum/ente"

func (r *Repository) createPasskey(newPasskey *ente.Passkey, credential *ente.PasskeyCredential) error {
	tx, err := r.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	_, err = tx.Exec(`
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

	if err != nil {
		return err
	}

	_, err = tx.Exec(`
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
		return err
	}

	return tx.Commit()
}
