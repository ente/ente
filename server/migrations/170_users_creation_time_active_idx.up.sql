CREATE INDEX CONCURRENTLY users_creation_time_active_idx
    ON users (creation_time)
    WHERE encrypted_email IS NOT NULL;
