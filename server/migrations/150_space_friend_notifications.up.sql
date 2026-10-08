LOCK TABLE space_friend_requests, space_messages IN SHARE ROW EXCLUSIVE MODE;

ALTER TABLE space_notifications
    ADD COLUMN friend_request_id BIGINT REFERENCES space_friend_requests (request_id) ON DELETE CASCADE,
    DROP CONSTRAINT space_notifications_check1,
    ADD CONSTRAINT chk_space_notifications_target CHECK (
        (kind = 'post_like' AND post_like_id IS NOT NULL AND friend_request_id IS NULL)
        OR (kind = 'friend_request' AND friend_request_id IS NOT NULL AND post_like_id IS NULL)
        OR (kind = 'friend_accepted' AND post_like_id IS NULL AND friend_request_id IS NULL)
    );

CREATE UNIQUE INDEX idx_space_notifications_friend_request
    ON space_notifications (friend_request_id) WHERE friend_request_id IS NOT NULL;

INSERT INTO space_notifications (
    notification_id, recipient_space_id, actor_space_id, kind, friend_request_id, created_at
)
SELECT 'wnot_request_' || request_id, target_space_id, requester_space_id, 'friend_request', request_id, created_at
FROM space_friend_requests;

INSERT INTO space_notifications (
    notification_id, recipient_space_id, actor_space_id, kind, created_at, read_at
)
SELECT m.message_id, m.recipient_space_id, m.sender_space_id, 'friend_accepted', m.created_at,
       CASE WHEN marker.read_at >= m.created_at THEN marker.read_at END
FROM space_messages m
LEFT JOIN space_notification_read_markers marker
    ON marker.viewer_space_id = m.recipient_space_id AND marker.friend_space_id = m.sender_space_id
WHERE m.kind = 'friend_added';

DELETE FROM space_messages WHERE kind = 'friend_added';

ALTER TABLE space_messages DROP CONSTRAINT chk_space_messages_kind;
ALTER TABLE space_messages ADD CONSTRAINT chk_space_messages_kind
    CHECK (kind IN ('regular', 'post_reply'));
