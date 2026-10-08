LOCK TABLE space_messages IN SHARE ROW EXCLUSIVE MODE;

CREATE TABLE space_post_likes (
    like_id TEXT PRIMARY KEY,
    post_id BIGINT NOT NULL REFERENCES space_posts (post_id) ON DELETE CASCADE,
    actor_space_id TEXT NOT NULL REFERENCES spaces (space_id) ON DELETE CASCADE,
    created_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    UNIQUE (post_id, actor_space_id)
);

CREATE TABLE space_notifications (
    notification_id TEXT PRIMARY KEY,
    recipient_space_id TEXT NOT NULL REFERENCES spaces (space_id) ON DELETE CASCADE,
    actor_space_id TEXT NOT NULL REFERENCES spaces (space_id) ON DELETE CASCADE,
    kind TEXT NOT NULL,
    post_like_id TEXT REFERENCES space_post_likes (like_id) ON DELETE CASCADE,
    created_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    read_at BIGINT,
    CHECK (recipient_space_id <> actor_space_id),
    CHECK (kind = 'post_like' AND post_like_id IS NOT NULL),
    UNIQUE (recipient_space_id, kind, post_like_id)
);

CREATE INDEX idx_space_notifications_recipient_created
    ON space_notifications (recipient_space_id, created_at DESC, notification_id DESC);

CREATE INDEX idx_space_notifications_unread
    ON space_notifications (recipient_space_id)
    WHERE read_at IS NULL;

CREATE INDEX idx_space_notifications_post_like
    ON space_notifications (post_like_id);

INSERT INTO space_post_likes (like_id, post_id, actor_space_id, created_at)
SELECT m.message_id, m.reply_post_id, m.sender_space_id, m.created_at
FROM space_messages m
JOIN space_posts p ON p.post_id = m.reply_post_id AND p.is_deleted = FALSE
WHERE m.kind = 'post_like';

INSERT INTO space_notifications (
    notification_id, recipient_space_id, actor_space_id, kind, post_like_id, created_at, read_at
)
SELECT 'wnot_' || l.like_id, p.space_id, l.actor_space_id, 'post_like', l.like_id, l.created_at,
       CASE WHEN marker.read_at >= l.created_at THEN marker.read_at END
FROM space_post_likes l
JOIN space_posts p ON p.post_id = l.post_id
LEFT JOIN space_notification_read_markers marker
    ON marker.viewer_space_id = p.space_id AND marker.friend_space_id = l.actor_space_id;

DELETE FROM space_messages WHERE kind = 'post_like';

ALTER TABLE space_messages DROP CONSTRAINT chk_space_messages_kind;
ALTER TABLE space_messages ADD CONSTRAINT chk_space_messages_kind
    CHECK (kind IN ('regular', 'post_reply', 'friend_added'));
