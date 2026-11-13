ALTER TABLE notification_history
    ADD COLUMN IF NOT EXISTS notification_group TEXT;

CREATE INDEX IF NOT EXISTS notification_history_user_template_sent_time_idx
    ON notification_history(user_id, template_id, sent_time DESC);

CREATE INDEX IF NOT EXISTS notification_history_group_user_id_idx
    ON notification_history(notification_group, user_id);
