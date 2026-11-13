DROP TRIGGER IF EXISTS check_reaction_target ON reactions;
DROP TRIGGER IF EXISTS update_reactions_updated_at ON reactions;
DROP TRIGGER IF EXISTS reactions_null_cipher_on_delete ON reactions;

DROP TRIGGER IF EXISTS soft_delete_reactions_on_comment_delete ON comments;
DROP TRIGGER IF EXISTS check_reply_scope ON comments;
DROP TRIGGER IF EXISTS update_comments_updated_at ON comments;
DROP TRIGGER IF EXISTS comments_null_cipher_on_delete ON comments;

DROP INDEX IF EXISTS idx_reactions_user;
DROP INDEX IF EXISTS idx_reactions_anon;
DROP INDEX IF EXISTS idx_reactions_comment;
DROP INDEX IF EXISTS idx_reactions_collection_updated_at;
DROP INDEX IF EXISTS idx_reactions_scope;

DROP INDEX IF EXISTS idx_comments_collection_updated_at;
DROP INDEX IF EXISTS idx_comments_user;
DROP INDEX IF EXISTS idx_comments_parent;
DROP INDEX IF EXISTS idx_comments_scope;
DROP INDEX IF EXISTS idx_comments_anon;

DROP INDEX IF EXISTS idx_anon_users_collection;

DROP TRIGGER IF EXISTS update_anon_users_updated_at ON anon_users;

DROP TABLE IF EXISTS reactions;
DROP TABLE IF EXISTS comments;
DROP TABLE IF EXISTS anon_users;

DROP FUNCTION IF EXISTS tg_soft_delete_reactions_on_comment_delete();
DROP FUNCTION IF EXISTS tg_check_reaction_target();
DROP FUNCTION IF EXISTS tg_check_reply_scope();
DROP FUNCTION IF EXISTS tg_null_cipher_on_delete();
