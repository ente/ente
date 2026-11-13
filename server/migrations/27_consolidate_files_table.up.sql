CREATE TYPE OBJECT_TYPE as ENUM ('file', 'thumbnail');

CREATE TABLE IF NOT EXISTS object_keys
(
    file_id     BIGINT      NOT NULL,
    o_type      OBJECT_TYPE NOT NULL,
    object_key  TEXT UNIQUE NOT NULL,
    size        bigint     NOT NULL,
    datacenters s3region[]  NOT NULL,
    is_deleted   bool   DEFAULT false,
    created_at  bigint DEFAULT now_utc_micro_seconds(),
    updated_at  bigint DEFAULT now_utc_micro_seconds(),
    PRIMARY KEY (file_id, o_type),
    CONSTRAINT fk_object_keys_file_id
        FOREIGN KEY (file_id)
            REFERENCES files (file_id)
            ON DELETE CASCADE
);

CREATE TRIGGER update_object_keys_updated_at
    BEFORE UPDATE
    ON object_keys
    FOR EACH ROW
EXECUTE PROCEDURE
    trigger_updated_at_microseconds_column();

BEGIN;
INSERT INTO object_keys(file_id, o_type, object_key, size, datacenters)
SELECT file_id, 'file', object_key,size, datacenters FROM file_object_keys;

INSERT INTO object_keys(file_id, o_type, object_key, size, datacenters)
SELECT file_id, 'thumbnail', object_key,size, datacenters FROM thumbnail_object_keys;
COMMIT;
