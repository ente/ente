DROP INDEX IF EXISTS notification_history_group_user_id_idx;
DROP INDEX IF EXISTS notification_history_user_template_sent_time_idx;

ALTER TABLE notification_history
    DROP COLUMN IF EXISTS notification_group;
