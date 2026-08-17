
DROP INDEX IF EXISTS idx_file_data_user_type_deleted;
DROP INDEX IF EXISTS idx_file_data_last_sync_time;

DROP TABLE IF EXISTS file_data;

DROP TYPE IF EXISTS file_data_type;

DROP TRIGGER IF EXISTS check_no_common_entries ON file_data;