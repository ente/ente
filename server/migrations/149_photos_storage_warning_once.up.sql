CREATE UNIQUE INDEX CONCURRENTLY notification_history_photos_storage_warning_once
    ON notification_history(user_id, template_id)
    WHERE template_id IN ('photos_storage_90_percent', 'photos_storage_reminder');
