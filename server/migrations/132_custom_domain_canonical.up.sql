ALTER TABLE remote_store ADD COLUMN canonical_value TEXT;

CREATE UNIQUE INDEX remote_store_custom_domain_canonical_unique_idx
    ON remote_store (canonical_value)
    WHERE key_name = 'customDomain' AND canonical_value IS NOT NULL;
