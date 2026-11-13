ALTER TABLE temp_objects
    ADD COLUMN user_id BIGINT,
    ADD COLUMN created_at BIGINT,
    ADD COLUMN app TEXT,
    ADD COLUMN purpose TEXT,
    ADD COLUMN content_length BIGINT,
    ADD COLUMN content_md5 TEXT,
    ADD COLUMN client VARCHAR(256);

ALTER TABLE temp_objects
    ALTER COLUMN created_at SET DEFAULT now_utc_micro_seconds();

ALTER TABLE space_temp_objects
    ADD COLUMN content_md5 TEXT,
    ADD COLUMN client VARCHAR(256);
