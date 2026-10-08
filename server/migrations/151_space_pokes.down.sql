DELETE FROM space_notifications WHERE kind = 'poke';

ALTER TABLE space_notifications
    DROP CONSTRAINT chk_space_notifications_target,
    DROP COLUMN poke_id,
    ADD CONSTRAINT chk_space_notifications_target CHECK (
        (kind = 'post_like' AND post_like_id IS NOT NULL AND friend_request_id IS NULL)
        OR (kind = 'friend_request' AND friend_request_id IS NOT NULL AND post_like_id IS NULL)
        OR (kind = 'friend_accepted' AND post_like_id IS NULL AND friend_request_id IS NULL)
    );

DROP TABLE space_pokes;
