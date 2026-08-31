ALTER TABLE tokens
    VALIDATE CONSTRAINT tokens_token_hash_present,
    VALIDATE CONSTRAINT tokens_token_hash_length;
