ALTER TABLE files
    ADD COLUMN app app,
    ADD CONSTRAINT files_app_supported
        CHECK (app IN ('photos', 'locker'))
        NOT VALID;

ALTER TABLE usage
    ADD COLUMN file_app_ready BOOLEAN NOT NULL DEFAULT FALSE;
