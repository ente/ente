ALTER TABLE usage
    ADD COLUMN photos_file_count BIGINT,
    ADD COLUMN locker_file_count BIGINT,
    ADD COLUMN file_count_source_version BIGINT NOT NULL DEFAULT 0,
    ADD CONSTRAINT usage_file_counts_both_ready_or_both_unknown
        CHECK ((photos_file_count IS NULL) = (locker_file_count IS NULL))
        NOT VALID;
