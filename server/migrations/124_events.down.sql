DROP TRIGGER IF EXISTS update_events_updated_at ON events;
DROP INDEX IF EXISTS events_user_id_idx;
DROP INDEX IF EXISTS events_id_event_idx;
DROP TABLE IF EXISTS events;
