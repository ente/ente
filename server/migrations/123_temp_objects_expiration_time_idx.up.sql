CREATE INDEX CONCURRENTLY IF NOT EXISTS temp_objects_expiration_time_idx
    ON temp_objects (expiration_time);
