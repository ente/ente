BEGIN;

ALTER TABLE tokens
    ALTER COLUMN token_hash SET NOT NULL;

ALTER TABLE tokens
    DROP CONSTRAINT tokens_token_hash_present;

COMMIT;
