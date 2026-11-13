CREATE UNIQUE INDEX IF NOT EXISTS collections_favorites_constraint_index_v2 ON collections (owner_id, app)
WHERE (type = 'favorites');

DROP INDEX IF EXISTS collections_favorites_constraint_index;
