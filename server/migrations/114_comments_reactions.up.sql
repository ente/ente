-- App supplies nanoid strings for primary keys; no pgcrypto dependency.

CREATE OR REPLACE FUNCTION tg_null_cipher_on_delete() RETURNS trigger AS $$
BEGIN
  IF NEW.is_deleted THEN
    NEW.cipher := NULL;
    NEW.nonce := NULL;
  END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION tg_check_reply_scope() RETURNS trigger AS $$
BEGIN
  IF NEW.parent_comment_id IS NULL THEN
    RETURN NEW;
  END IF;
  PERFORM 1 FROM comments p
   WHERE p.id = NEW.parent_comment_id
     AND p.collection_id = NEW.collection_id
     AND (p.file_id IS NOT DISTINCT FROM NEW.file_id);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reply must match parent scope';
  END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION tg_check_reaction_target() RETURNS trigger AS $$
DECLARE
  c_rec RECORD;
BEGIN
  IF NEW.comment_id IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT id, collection_id INTO c_rec FROM comments WHERE id = NEW.comment_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reaction must reference an existing comment';
  END IF;
  IF c_rec.collection_id <> NEW.collection_id THEN
    RAISE EXCEPTION 'Reaction collection_id must match comment collection_id';
  END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS anon_users (
  id TEXT PRIMARY KEY,
  collection_id BIGINT NOT NULL,
  cipher TEXT NOT NULL,
  nonce TEXT NOT NULL,
  created_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
  updated_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds()
);

CREATE INDEX IF NOT EXISTS idx_anon_users_collection
  ON anon_users (collection_id);

CREATE TRIGGER update_anon_users_updated_at
  BEFORE UPDATE ON anon_users
  FOR EACH ROW EXECUTE PROCEDURE trigger_updated_at_microseconds_column();

CREATE OR REPLACE FUNCTION tg_soft_delete_reactions_on_comment_delete() RETURNS trigger AS $$
BEGIN
  IF NEW.is_deleted AND (OLD.is_deleted IS DISTINCT FROM NEW.is_deleted) THEN
    UPDATE reactions
       SET is_deleted = TRUE,
           cipher = NULL,
           nonce = NULL,
           updated_at = now_utc_micro_seconds()
     WHERE comment_id = NEW.id
       AND is_deleted = FALSE;
  END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS comments (
  id TEXT PRIMARY KEY,

  collection_id BIGINT NOT NULL,
  file_id BIGINT NULL, -- null => collection-level comment

  parent_comment_id TEXT NULL, -- reply-to (same collection_id/file_id)
  user_id BIGINT NOT NULL,
  anon_user_id TEXT NULL,

  cipher TEXT,
  nonce TEXT,

  is_deleted BOOLEAN NOT NULL DEFAULT FALSE,

  created_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
  updated_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),

  CONSTRAINT comments_cipher_on_delete CHECK (
    (is_deleted = FALSE AND cipher IS NOT NULL AND nonce IS NOT NULL) OR
    (is_deleted = TRUE  AND cipher IS NULL AND nonce IS NULL)
  ),
  CONSTRAINT comments_user_or_anon_chk CHECK (
    (user_id = -1 AND anon_user_id IS NOT NULL) OR
    (user_id > 0  AND anon_user_id IS NULL)
  ),
  CONSTRAINT fk_comments_anon_user FOREIGN KEY (anon_user_id) REFERENCES anon_users (id)
);

CREATE INDEX IF NOT EXISTS idx_comments_scope
  ON comments (collection_id, file_id)
  WHERE is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_comments_parent
  ON comments (parent_comment_id)
  WHERE is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_comments_user
  ON comments (user_id)
  WHERE is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_comments_anon
  ON comments (anon_user_id)
  WHERE is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_comments_collection_updated_at
  ON comments (collection_id, updated_at);

CREATE TRIGGER comments_null_cipher_on_delete
  BEFORE INSERT OR UPDATE ON comments
  FOR EACH ROW EXECUTE PROCEDURE tg_null_cipher_on_delete();

CREATE TRIGGER update_comments_updated_at
  BEFORE UPDATE ON comments
  FOR EACH ROW EXECUTE PROCEDURE trigger_updated_at_microseconds_column();

CREATE TRIGGER check_reply_scope
  BEFORE INSERT OR UPDATE ON comments
  FOR EACH ROW EXECUTE PROCEDURE tg_check_reply_scope();

CREATE TRIGGER soft_delete_reactions_on_comment_delete
  AFTER UPDATE ON comments
  FOR EACH ROW WHEN (NEW.is_deleted)
  EXECUTE PROCEDURE tg_soft_delete_reactions_on_comment_delete();

CREATE TABLE IF NOT EXISTS reactions (
  id TEXT PRIMARY KEY,

  collection_id BIGINT NOT NULL,
  file_id BIGINT NULL,     -- present when reacting to a file in a collection
  comment_id TEXT NULL,    -- present when reacting to a specific comment

  user_id BIGINT NOT NULL, -- reactor
  anon_user_id TEXT NULL,

  actor_key TEXT GENERATED ALWAYS AS (
    CASE
      WHEN user_id = -1 AND anon_user_id IS NOT NULL THEN 'A:' || anon_user_id
      ELSE 'U:' || user_id::TEXT
    END
  ) STORED,

  cipher TEXT,
  nonce TEXT,

  is_deleted BOOLEAN NOT NULL DEFAULT FALSE,

  created_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
  updated_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),

  CONSTRAINT reactions_target_shape CHECK (
    (comment_id IS NOT NULL AND file_id IS NULL)
    OR
    (comment_id IS NULL)
  ),

  CONSTRAINT reactions_cipher_on_delete CHECK (
    (is_deleted = FALSE AND cipher IS NOT NULL AND nonce IS NOT NULL) OR
    (is_deleted = TRUE  AND cipher IS NULL AND nonce IS NULL)
  ),

  unique_key TEXT GENERATED ALWAYS AS (
    CASE
      WHEN comment_id IS NOT NULL THEN 'M:' || comment_id::TEXT
      WHEN file_id    IS NOT NULL THEN 'F:' || collection_id::TEXT || '/' || file_id::TEXT
      ELSE                             'C:' || collection_id::TEXT
    END
  ) STORED,

  CONSTRAINT uq_reactions_actor_target UNIQUE (actor_key, unique_key),
  CONSTRAINT reactions_user_or_anon_chk CHECK (
    (user_id = -1 AND anon_user_id IS NOT NULL) OR
    (user_id > 0  AND anon_user_id IS NULL)
  ),
  CONSTRAINT fk_reactions_anon_user FOREIGN KEY (anon_user_id) REFERENCES anon_users (id)
);

CREATE INDEX IF NOT EXISTS idx_reactions_scope
  ON reactions (collection_id, file_id, comment_id)
  WHERE is_deleted = FALSE;
 
CREATE INDEX IF NOT EXISTS idx_reactions_collection_updated_at
  ON reactions (collection_id, updated_at);

CREATE INDEX IF NOT EXISTS idx_reactions_comment
  ON reactions (comment_id)
  WHERE is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_reactions_user
  ON reactions (user_id)
  WHERE is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_reactions_anon
  ON reactions (anon_user_id)
  WHERE is_deleted = FALSE;

CREATE TRIGGER reactions_null_cipher_on_delete
  BEFORE INSERT OR UPDATE ON reactions
  FOR EACH ROW EXECUTE PROCEDURE tg_null_cipher_on_delete();

CREATE TRIGGER update_reactions_updated_at
  BEFORE UPDATE ON reactions
  FOR EACH ROW EXECUTE PROCEDURE trigger_updated_at_microseconds_column();

CREATE TRIGGER check_reaction_target
  BEFORE INSERT OR UPDATE ON reactions
  FOR EACH ROW EXECUTE PROCEDURE tg_check_reaction_target();
