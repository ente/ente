CREATE TABLE space_comments (
    comment_id TEXT PRIMARY KEY,
    post_id BIGINT NOT NULL REFERENCES space_posts (post_id) ON DELETE CASCADE,
    author_space_id TEXT REFERENCES spaces (space_id) ON DELETE SET NULL,
    parent_id TEXT REFERENCES space_comments (comment_id) ON DELETE CASCADE,
    reply_to_id TEXT REFERENCES space_comments (comment_id),
    cipher BYTEA,
    created_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds()
);
CREATE INDEX space_comments_post ON space_comments (post_id, created_at, comment_id);
CREATE INDEX space_comments_author ON space_comments (author_space_id, post_id);
CREATE INDEX space_comments_parent ON space_comments (parent_id);
CREATE INDEX space_comments_reply_to ON space_comments (reply_to_id);
CREATE TABLE space_comment_reactions (
    comment_id TEXT NOT NULL REFERENCES space_comments (comment_id) ON DELETE CASCADE,
    actor_space_id TEXT NOT NULL REFERENCES spaces (space_id) ON DELETE CASCADE,
    cipher BYTEA NOT NULL,
    PRIMARY KEY (comment_id, actor_space_id)
);

ALTER TABLE space_notifications ADD COLUMN comment_id TEXT REFERENCES space_comments (comment_id) ON DELETE CASCADE;
ALTER TABLE space_notifications DROP CONSTRAINT chk_space_notifications_target;
ALTER TABLE space_notifications ADD CONSTRAINT chk_space_notifications_target CHECK (
    (kind = 'post_like' AND post_like_id IS NOT NULL AND friend_request_id IS NULL AND poke_id IS NULL AND comment_id IS NULL)
    OR (kind = 'friend_request' AND friend_request_id IS NOT NULL AND post_like_id IS NULL AND poke_id IS NULL AND comment_id IS NULL)
    OR (kind = 'friend_accepted' AND post_like_id IS NULL AND friend_request_id IS NULL AND poke_id IS NULL AND comment_id IS NULL)
    OR (kind = 'poke' AND poke_id IS NOT NULL AND post_like_id IS NULL AND friend_request_id IS NULL AND comment_id IS NULL)
    OR (kind IN ('comment', 'comment_reply', 'comment_reaction') AND comment_id IS NOT NULL AND post_like_id IS NULL AND friend_request_id IS NULL AND poke_id IS NULL)
);
CREATE UNIQUE INDEX space_comment_notification ON space_notifications (recipient_space_id, actor_space_id, kind, comment_id) WHERE comment_id IS NOT NULL;
CREATE INDEX space_notifications_comment ON space_notifications (comment_id) WHERE comment_id IS NOT NULL;

CREATE FUNCTION space_comment_author_deleted() RETURNS TRIGGER AS $$
BEGIN
    NEW.cipher = NULL;
    DELETE FROM space_comment_reactions WHERE comment_id = OLD.comment_id;
    DELETE FROM space_notifications WHERE comment_id = OLD.comment_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER space_comment_author_deleted BEFORE UPDATE OF author_space_id ON space_comments
    FOR EACH ROW WHEN (NEW.author_space_id IS NULL) EXECUTE FUNCTION space_comment_author_deleted();
