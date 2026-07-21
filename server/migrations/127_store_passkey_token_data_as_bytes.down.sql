-- Passkey login sessions are short-lived. Clear active responses before restoring
-- JSONB so a legacy NUL-byte hash cannot make the rollback fail.
UPDATE passkey_login_sessions
SET token_data = NULL, verified_at = NULL;

ALTER TABLE passkey_login_sessions
    ALTER COLUMN token_data TYPE JSONB
    USING convert_from(token_data, 'UTF8')::jsonb;
