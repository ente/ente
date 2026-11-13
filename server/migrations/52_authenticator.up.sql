
 CREATE TABLE IF NOT EXISTS authenticator_key (
    user_id       BIGINT  PRIMARY KEY  NOT NULL,
    encrypted_key TEXT NOT NULL,
    header        TEXT NOT NULL,
    created_at    BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at    BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    CONSTRAINT fk_authenticator_key_user_id FOREIGN KEY (user_id) REFERENCES users (
         user_id) ON DELETE CASCADE
 );


 CREATE TABLE IF NOT EXISTS authenticator_entity
 (
     id                 uuid PRIMARY KEY NOT NULL,
     user_id            BIGINT NOT NULL,
     encrypted_data     TEXT,
     header             TEXT,
     created_at         BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
     updated_at         BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
	 is_deleted         BOOLEAN DEFAULT FALSE,
     CONSTRAINT fk_authenticator_key_user_id FOREIGN KEY (user_id) REFERENCES authenticator_key (
     user_id) ON DELETE CASCADE
 );

CREATE INDEX IF NOT EXISTS authenticator_entity_updated_at_time_index ON authenticator_entity (user_id, updated_at);

ALTER TABLE authenticator_entity
    ADD CONSTRAINT authenticator_entity_state_constraint CHECK ((is_deleted is TRUE AND encrypted_data IS NULL) or (is_deleted is FALSE AND encrypted_data IS NOT NULL));

CREATE TRIGGER update_authenticator_entity_updated_at
    BEFORE UPDATE
    ON authenticator_entity
    FOR EACH ROW
EXECUTE PROCEDURE
    trigger_updated_at_microseconds_column();


CREATE OR REPLACE FUNCTION fn_update_authenticator_key_updated_at_via_updated_at() RETURNS TRIGGER AS $$
BEGIN
    IF  (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
        UPDATE authenticator_key SET updated_at = NEW.updated_at where user_id = new.user_id and
                updated_at < New.updated_at;
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_authenticator_key_updated_time_on_authenticator_entity_updation
    AFTER INSERT OR UPDATE
    ON authenticator_entity
    FOR EACH ROW
EXECUTE PROCEDURE
    fn_update_authenticator_key_updated_at_via_updated_at();
