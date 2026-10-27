DROP TRIGGER space_comment_author_deleted ON space_comments;
DROP FUNCTION space_comment_author_deleted();
DELETE FROM space_notifications WHERE comment_id IS NOT NULL;
ALTER TABLE space_notifications DROP CONSTRAINT chk_space_notifications_target;
ALTER TABLE space_notifications DROP COLUMN comment_id;
ALTER TABLE space_notifications ADD CONSTRAINT chk_space_notifications_target CHECK (
    (kind = 'post_like' AND post_like_id IS NOT NULL AND friend_request_id IS NULL AND poke_id IS NULL)
    OR (kind = 'friend_request' AND friend_request_id IS NOT NULL AND post_like_id IS NULL AND poke_id IS NULL)
    OR (kind = 'friend_accepted' AND post_like_id IS NULL AND friend_request_id IS NULL AND poke_id IS NULL)
    OR (kind = 'poke' AND poke_id IS NOT NULL AND post_like_id IS NULL AND friend_request_id IS NULL)
);
DROP TABLE space_comment_reactions, space_comments;
