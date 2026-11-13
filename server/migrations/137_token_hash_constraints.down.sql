ALTER TABLE tokens
    DROP CONSTRAINT tokens_token_hash_present,
    DROP CONSTRAINT tokens_token_hash_length;
