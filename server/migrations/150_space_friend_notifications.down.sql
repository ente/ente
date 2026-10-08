ALTER TABLE space_messages DROP CONSTRAINT chk_space_messages_kind;
ALTER TABLE space_messages ADD CONSTRAINT chk_space_messages_kind
    CHECK (kind IN ('regular', 'post_reply', 'friend_added'));

INSERT INTO space_messages (
    message_id, sender_space_id, recipient_space_id, kind, created_at, updated_at
)
SELECT notification_id, actor_space_id, recipient_space_id, 'friend_added', created_at, created_at
FROM space_notifications WHERE kind = 'friend_accepted';

DELETE FROM space_notifications WHERE kind IN ('friend_request', 'friend_accepted');

ALTER TABLE space_notifications
    DROP CONSTRAINT chk_space_notifications_target,
    DROP COLUMN friend_request_id,
    ADD CONSTRAINT space_notifications_check1 CHECK (kind = 'post_like' AND post_like_id IS NOT NULL);
