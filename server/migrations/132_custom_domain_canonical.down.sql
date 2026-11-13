DROP INDEX IF EXISTS remote_store_custom_domain_canonical_unique_idx;

ALTER TABLE remote_store DROP COLUMN canonical_value;
