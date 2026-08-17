CREATE OR REPLACE FUNCTION now_utc_micro_seconds() RETURNS BIGINT AS
$$
SELECT CAST(extract(EPOCH from now() at time zone 'utc') * 1000000 as BIGINT) ;
$$ language sql;

CREATE OR REPLACE FUNCTION trigger_updated_at_microseconds_column()
    RETURNS TRIGGER AS
$$
BEGIN
    NEW.updated_at = now_utc_micro_seconds();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TABLE IF NOT EXISTS location_tag
(
    id                   uuid PRIMARY KEY NOT NULL,
    user_id              INTEGER          NOT NULL,
    provider             TEXT             NOT NULL DEFAULT 'USER',
    is_deleted           BOOLEAN          NOT NULL DEFAULT FALSE,
    created_at           bigint           NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at           bigint           NOT NULL DEFAULT now_utc_micro_seconds(),
    encrypted_key        TEXT             NOT NULL,
    key_decryption_nonce TEXT             NOT NULL,
    attributes           JSONB            NOT NULL,
    CONSTRAINT fk_location_tag_user_id
        FOREIGN KEY (user_id)
            REFERENCES users (user_id)
            ON DELETE CASCADE
);

CREATE TRIGGER update_location_tag_updated_at
    BEFORE UPDATE
    ON location_tag
    FOR EACH ROW
EXECUTE PROCEDURE
    trigger_updated_at_microseconds_column();
