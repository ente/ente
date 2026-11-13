CREATE TABLE IF NOT EXISTS space_web_push_subscriptions (
    target_id          TEXT   PRIMARY KEY,
    endpoint           TEXT   NOT NULL,
    session_token_hash BYTEA  UNIQUE
        REFERENCES space_browser_sessions (token_hash) ON DELETE CASCADE,
    link_id            BIGINT
        REFERENCES space_links (link_id) ON DELETE CASCADE,
    p256dh             TEXT   NOT NULL,
    auth               TEXT   NOT NULL,
    created_at         BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at         BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    CONSTRAINT chk_space_web_push_subscription_target CHECK (
        (session_token_hash IS NOT NULL AND link_id IS NULL)
        OR
        (session_token_hash IS NULL AND link_id IS NOT NULL)
    ),
    CONSTRAINT uq_space_web_push_link UNIQUE (endpoint, link_id)
);

CREATE UNIQUE INDEX uq_space_web_push_account_endpoint
    ON space_web_push_subscriptions (endpoint)
    WHERE session_token_hash IS NOT NULL;

CREATE INDEX idx_space_web_push_link
    ON space_web_push_subscriptions (link_id)
    WHERE link_id IS NOT NULL;

CREATE TRIGGER update_space_web_push_subscriptions_updated_at
    BEFORE UPDATE ON space_web_push_subscriptions
    FOR EACH ROW
EXECUTE PROCEDURE trigger_updated_at_microseconds_column();
