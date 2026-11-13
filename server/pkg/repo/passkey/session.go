package passkey

import (
	"github.com/ente/museum/ente"
	"github.com/google/uuid"
)

func (r *Repository) getWebAuthnSessionByID(sessionID uuid.UUID) (session *ente.WebAuthnSession, err error) {

	session = &ente.WebAuthnSession{}

	err = r.DB.QueryRow(`
		DELETE FROM webauthn_sessions
		WHERE id = $1
		RETURNING
			id,
			challenge,
			user_id,
			COALESCE(rp_id, '') AS rp_id,
			allowed_credential_ids,
			expires_at,
			user_verification_requirement,
			extensions,
			created_at
	`, sessionID).Scan(
		&session.ID,
		&session.Challenge,
		&session.UserID,
		&session.RPID,
		&session.AllowedCredentialIDs,
		&session.ExpiresAt,
		&session.UserVerificationRequirement,
		&session.Extensions,
		&session.CreatedAt,
	)

	return
}
