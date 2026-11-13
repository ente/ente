ALTER TABLE space_temp_objects
    DROP COLUMN content_md5,
    DROP COLUMN client;

ALTER TABLE temp_objects
    DROP COLUMN user_id,
    DROP COLUMN created_at,
    DROP COLUMN app,
    DROP COLUMN purpose,
    DROP COLUMN content_length,
    DROP COLUMN content_md5,
    DROP COLUMN client;
