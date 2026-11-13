CREATE TABLE IF NOT EXISTS events (
    id TEXT NOT NULL,
    event TEXT NOT NULL,
    app TEXT NOT NULL,
    platform TEXT NOT NULL,
    data JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(data) = 'object'),
    user_id BIGINT,
    created_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds()
);

CREATE UNIQUE INDEX IF NOT EXISTS events_id_event_idx ON events(id, event);
CREATE INDEX IF NOT EXISTS events_user_id_idx ON events(user_id);

CREATE TRIGGER update_events_updated_at
    BEFORE UPDATE
    ON events
    FOR EACH ROW
EXECUTE PROCEDURE
    trigger_updated_at_microseconds_column();
