CREATE TABLE space_pokes (
    poke_id TEXT PRIMARY KEY,
    sender_space_id TEXT NOT NULL REFERENCES spaces (space_id) ON DELETE CASCADE,
    recipient_space_id TEXT NOT NULL REFERENCES spaces (space_id) ON DELETE CASCADE,
    client_request_id TEXT NOT NULL,
    created_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    CHECK (sender_space_id <> recipient_space_id),
    UNIQUE (sender_space_id, recipient_space_id, client_request_id)
);

CREATE INDEX idx_space_pokes_recipient_created
    ON space_pokes (recipient_space_id, created_at DESC);

ALTER TABLE space_notifications
    ADD COLUMN poke_id TEXT REFERENCES space_pokes (poke_id) ON DELETE CASCADE,
    DROP CONSTRAINT chk_space_notifications_target,
    ADD CONSTRAINT chk_space_notifications_target CHECK (
        (kind = 'post_like' AND post_like_id IS NOT NULL AND friend_request_id IS NULL AND poke_id IS NULL)
        OR (kind = 'friend_request' AND friend_request_id IS NOT NULL AND post_like_id IS NULL AND poke_id IS NULL)
        OR (kind = 'friend_accepted' AND post_like_id IS NULL AND friend_request_id IS NULL AND poke_id IS NULL)
        OR (kind = 'poke' AND poke_id IS NOT NULL AND post_like_id IS NULL AND friend_request_id IS NULL)
    );

CREATE UNIQUE INDEX idx_space_notifications_poke ON space_notifications (poke_id);
