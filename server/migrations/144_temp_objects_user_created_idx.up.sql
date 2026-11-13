CREATE INDEX CONCURRENTLY temp_objects_user_created_idx
    ON temp_objects (user_id, created_at);
