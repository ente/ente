DROP INDEX IF EXISTS collections_uncategorized_constraint_index_v2;

CREATE UNIQUE INDEX IF NOT EXISTS collections_uncategorized_constraint_index ON collections (owner_id, app)
WHERE (type = 'uncategorized');

ALTER TABLE collections ALTER COLUMN app DROP NOT NULL;

ALTER TABLE collections ALTER COLUMN app DROP DEFAULT;

UPDATE collections SET app = NULL WHERE app = 'photos';
