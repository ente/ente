CREATE INDEX CONCURRENTLY collection_files_recent_diff_idx
    ON collection_files (collection_id, updation_time)
    WHERE collection_id > 1580559969168390
        OR updation_time >= 1794960000000000;
