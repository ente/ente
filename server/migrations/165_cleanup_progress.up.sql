CREATE TABLE cleanup_progress (
    name TEXT PRIMARY KEY,
    last_key TEXT,
    upper_bound TEXT,
    rows_scanned BIGINT NOT NULL DEFAULT 0,
    rows_deleted BIGINT NOT NULL DEFAULT 0,
    next_batch_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ
);

INSERT INTO cleanup_progress (name) VALUES ('object_copies_completed_v1');
