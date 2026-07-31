DROP INDEX IF EXISTS idx_data_cleanup_scheduled_email_hash;

ALTER TABLE data_cleanup DROP COLUMN IF EXISTS email_hash;
