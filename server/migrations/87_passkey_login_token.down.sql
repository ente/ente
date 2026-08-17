ALTER TABLE passkey_login_sessions
    DROP COLUMN IF EXISTS token_fetch_cnt,
    DROP COLUMN IF EXISTS verified_at,
    DROP COLUMN IF EXISTS token_data;
