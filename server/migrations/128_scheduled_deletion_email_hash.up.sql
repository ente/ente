ALTER TABLE data_cleanup ADD COLUMN email_hash TEXT;

CREATE INDEX idx_data_cleanup_scheduled_email_hash
    ON data_cleanup (email_hash, created_at DESC)
    WHERE stage = 'scheduled' AND email_hash IS NOT NULL;
