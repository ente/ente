ALTER TYPE app ADD VALUE 'locker';

ALTER TABLE collections ADD COLUMN app app DEFAULT 'photos';

UPDATE collections SET app = 'photos' WHERE app IS NULL;

ALTER TABLE collections ALTER COLUMN app SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS collections_uncategorized_constraint_index_v2 ON collections (owner_id, app)
WHERE (type = 'uncategorized');

DROP INDEX IF EXISTS collections_uncategorized_constraint_index;