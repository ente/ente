ALTER TABLE space_messages DROP CONSTRAINT chk_space_messages_kind;
ALTER TABLE space_messages ADD CONSTRAINT chk_space_messages_kind
    CHECK (kind IN ('regular', 'post_reply', 'post_like', 'friend_added'));

INSERT INTO space_messages (
    message_id, sender_space_id, recipient_space_id, kind, reply_post_id, created_at, updated_at
)
SELECT l.like_id, l.actor_space_id, p.space_id, 'post_like', l.post_id, l.created_at, l.created_at
FROM space_post_likes l
JOIN space_posts p ON p.post_id = l.post_id AND p.is_deleted = FALSE;

INSERT INTO space_messages (
    message_id, sender_space_id, recipient_space_id, kind, created_at, updated_at
)
SELECT notification_id, actor_space_id, recipient_space_id, 'friend_added', created_at, created_at
FROM space_notifications WHERE kind = 'friend_accepted';

DROP TABLE space_notifications;
DROP TABLE space_post_likes;
DROP TABLE space_pokes;
