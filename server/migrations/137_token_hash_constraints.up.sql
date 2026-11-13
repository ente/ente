ALTER TABLE tokens
    ADD CONSTRAINT tokens_token_hash_present CHECK (token_hash IS NOT NULL) NOT VALID,
    ADD CONSTRAINT tokens_token_hash_length CHECK (octet_length(token_hash) = 32) NOT VALID;
