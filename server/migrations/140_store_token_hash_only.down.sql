BEGIN;

ALTER TABLE tokens ALTER COLUMN token SET NOT NULL;

CREATE OR REPLACE FUNCTION sync_token_hash() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.token IS NOT NULL THEN
        NEW.token_hash := sha256(convert_to(NEW.token, 'UTF8'));
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMIT;
