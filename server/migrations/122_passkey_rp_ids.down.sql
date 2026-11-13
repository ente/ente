ALTER TABLE webauthn_sessions
    DROP COLUMN IF EXISTS rp_id;

ALTER TABLE passkey_credentials
    DROP COLUMN IF EXISTS rp_id;
