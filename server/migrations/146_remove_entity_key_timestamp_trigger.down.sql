CREATE OR REPLACE FUNCTION fn_update_entity_key_updated_at_via_updated_at() RETURNS TRIGGER AS
$$
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
        UPDATE entity_key
        SET updated_at = NEW.updated_at
        WHERE user_id = NEW.user_id
          AND type = NEW.type
          AND updated_at < NEW.updated_at;
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_entity_key_on_entity_data_updation
    AFTER INSERT OR UPDATE
    ON entity_data
    FOR EACH ROW
EXECUTE PROCEDURE fn_update_entity_key_updated_at_via_updated_at();
