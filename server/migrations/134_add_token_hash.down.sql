BEGIN;

DROP TRIGGER sync_token_hash ON tokens;
DROP FUNCTION sync_token_hash();
ALTER TABLE tokens DROP COLUMN token_hash;

COMMIT;
