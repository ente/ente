ALTER TABLE usage
    DROP CONSTRAINT usage_file_counts_both_ready_or_both_unknown,
    DROP COLUMN file_count_source_version,
    DROP COLUMN locker_file_count,
    DROP COLUMN photos_file_count;
