ALTER TABLE usage
    DROP COLUMN file_app_ready;

ALTER TABLE files
    DROP CONSTRAINT files_app_supported,
    DROP COLUMN app;
