ALTER TABLE object_copies SET (
    autovacuum_vacuum_scale_factor = 0,
    autovacuum_vacuum_threshold = 5000000,
    autovacuum_vacuum_cost_limit = 2000
);
