DROP INDEX IF EXISTS collections_favorites_constraint_index_v2;

CREATE UNIQUE INDEX IF NOT EXISTS collections_favorites_constraint_index ON collections (owner_id)
WHERE (type = 'favorites');
