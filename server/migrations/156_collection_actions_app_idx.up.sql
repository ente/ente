CREATE INDEX CONCURRENTLY collection_actions_pending_user_app_action_time_idx
    ON collection_actions (user_id, app, action, updated_at)
    WHERE is_pending = true;
