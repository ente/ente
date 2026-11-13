BEGIN;

UPDATE space_links
SET active = FALSE
WHERE active = TRUE;

DELETE FROM space_web_push_subscriptions
WHERE link_id IN (
    SELECT link_id
    FROM space_links
    WHERE active = FALSE
);

COMMIT;
