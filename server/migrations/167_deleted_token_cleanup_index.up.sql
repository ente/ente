CREATE INDEX CONCURRENTLY tokens_deleted_last_used_at_idx ON tokens (last_used_at) WHERE is_deleted = TRUE;
