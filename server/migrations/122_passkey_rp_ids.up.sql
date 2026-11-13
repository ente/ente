ALTER TABLE passkey_credentials
    ADD COLUMN IF NOT EXISTS rp_id TEXT;

ALTER TABLE webauthn_sessions
    ADD COLUMN IF NOT EXISTS rp_id TEXT;
