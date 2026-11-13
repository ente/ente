ALTER TABLE push_tokens
    ADD COLUMN session_token_hash BYTEA;

CREATE INDEX push_tokens_session_token_hash_idx ON push_tokens (session_token_hash)
    WHERE session_token_hash IS NOT NULL;
