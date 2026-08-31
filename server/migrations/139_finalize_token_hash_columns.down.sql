ALTER TABLE tokens
    ALTER COLUMN token_hash DROP NOT NULL,
    ADD CONSTRAINT tokens_token_hash_present CHECK (token_hash IS NOT NULL);
