CREATE INDEX CONCURRENTLY IF NOT EXISTS collection_files_collection_id_updation_time_idx
    ON collection_files (collection_id, updation_time);
