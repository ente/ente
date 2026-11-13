CREATE TABLE IF NOT EXISTS entity_key
(
    user_id       BIGINT             NOT NULL,
    type          TEXT               NOT NULL,
    encrypted_key TEXT               NOT NULL,
    header        TEXT               NOT NULL,
    created_at    BIGINT             NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at    BIGINT             NOT NULL DEFAULT now_utc_micro_seconds(),
    PRIMARY KEY (user_id, type),
    CONSTRAINT fk_entity_key_user_id FOREIGN KEY (user_id) REFERENCES users (
                                                                             user_id) ON DELETE CASCADE
);


CREATE TABLE IF NOT EXISTS entity_data
(
    id             uuid PRIMARY KEY NOT NULL,
    user_id        BIGINT           NOT NULL,
    type           TEXT             NOT NULL,
    encrypted_data TEXT,
    header         TEXT,
    created_at     BIGINT           NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at     BIGINT           NOT NULL DEFAULT now_utc_micro_seconds(),
    is_deleted     BOOLEAN                   DEFAULT FALSE,
    CONSTRAINT fk_entity_key_user_id_and_type FOREIGN KEY (user_id, type) REFERENCES entity_key (user_id, type) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS entity_data_updated_at_time_index ON entity_data (user_id, updated_at);

ALTER TABLE entity_data
    ADD CONSTRAINT entity_data_state_constraint CHECK ((is_deleted is TRUE AND encrypted_data IS NULL) or
                                                       (is_deleted is FALSE AND encrypted_data IS NOT NULL));

CREATE TRIGGER update_entity_data_updated_at
    BEFORE UPDATE
    ON entity_data
    FOR EACH ROW
EXECUTE PROCEDURE
    trigger_updated_at_microseconds_column();


CREATE OR REPLACE FUNCTION fn_update_entity_key_updated_at_via_updated_at() RETURNS TRIGGER AS
$$
BEGIN
    IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
        UPDATE entity_key
        SET updated_at = NEW.updated_at
        where user_id = new.user_id
          and type = new.type
          and updated_at < New.updated_at;
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_entity_key_on_entity_data_updation
    AFTER INSERT OR UPDATE
    ON entity_data
    FOR EACH ROW
EXECUTE PROCEDURE
    fn_update_entity_key_updated_at_via_updated_at();
