BEGIN;

ALTER TABLE tokens ADD COLUMN token_hash BYTEA;

CREATE FUNCTION sync_token_hash() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.token IS NOT NULL THEN
        NEW.token_hash := sha256(convert_to(NEW.token, 'UTF8'));
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sync_token_hash
    BEFORE INSERT OR UPDATE OF token ON tokens
    FOR EACH ROW EXECUTE FUNCTION sync_token_hash();

COMMIT;
