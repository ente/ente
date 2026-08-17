ALTER TYPE s3region ADD VALUE 'wasabi-eu-central-2-derived';
DROP TRIGGER IF EXISTS update_embeddings_updated_at ON embeddings;
ALTER TABLE embeddings ADD COLUMN IF NOT EXISTS datacenters s3region[] default '{b2-eu-cen}';
