-- token_data is an opaque serialized response. JSONB rejects legacy key hashes
-- containing NUL bytes even though json.Marshal escapes them safely.
ALTER TABLE passkey_login_sessions
    ALTER COLUMN token_data TYPE BYTEA
    USING convert_to(token_data::text, 'UTF8');
