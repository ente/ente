CREATE INDEX CONCURRENTLY IF NOT EXISTS srp_sessions_created_at_idx
    ON srp_sessions (created_at);
