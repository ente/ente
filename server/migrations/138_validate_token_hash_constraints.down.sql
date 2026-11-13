ALTER TABLE tokens
    DROP CONSTRAINT tokens_token_hash_present,
    ADD CONSTRAINT tokens_token_hash_present CHECK (token_hash IS NOT NULL) NOT VALID,
    DROP CONSTRAINT tokens_token_hash_length,
    ADD CONSTRAINT tokens_token_hash_length CHECK (octet_length(token_hash) = 32) NOT VALID;
