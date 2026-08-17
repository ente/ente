CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_queue_created_at_non_deleted ON queue (queue_name, created_at)
    WHERE is_deleted = false;
