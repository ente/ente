CREATE TABLE IF NOT EXISTS spaces (
    space_id              TEXT PRIMARY KEY,
    owner_id             BIGINT NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    space_slug            TEXT   NOT NULL,
    root_wrapped_space_key BYTEA NOT NULL,
    public_key            BYTEA  NOT NULL,
    encrypted_secret_key  BYTEA  NOT NULL,
    encrypted_profile    BYTEA  NOT NULL DEFAULT '\x'::bytea,
    current_version      INTEGER NOT NULL DEFAULT 1,
    referred_by_space_id TEXT REFERENCES spaces (space_id) ON DELETE SET NULL,
    created_at           BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at           BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    CONSTRAINT uq_spaces_slug UNIQUE (space_slug),
    CONSTRAINT chk_spaces_referral_self CHECK (referred_by_space_id IS NULL OR referred_by_space_id <> space_id)
);

CREATE INDEX idx_spaces_owner ON spaces (owner_id);

CREATE TRIGGER update_spaces_updated_at
    BEFORE UPDATE ON spaces
    FOR EACH ROW
EXECUTE PROCEDURE trigger_updated_at_microseconds_column();

CREATE TABLE IF NOT EXISTS space_profile_assets (
    space_id      TEXT   NOT NULL REFERENCES spaces (space_id) ON DELETE CASCADE,
    asset_type    TEXT   NOT NULL,
    object_id     TEXT   NOT NULL,
    bucket_id     TEXT   NOT NULL,
    size          BIGINT,
    key_version   INTEGER NOT NULL,
    created_at    BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at    BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    PRIMARY KEY (space_id, asset_type),
    CONSTRAINT chk_space_profile_assets_type CHECK (asset_type IN ('avatar', 'cover')),
    CONSTRAINT chk_space_profile_assets_object_id CHECK (object_id <> '' AND object_id NOT LIKE '%/%'),
    CONSTRAINT chk_space_profile_assets_size CHECK (size IS NULL OR size > 0)
);

CREATE TRIGGER update_space_profile_assets_updated_at
    BEFORE UPDATE ON space_profile_assets
    FOR EACH ROW
EXECUTE PROCEDURE trigger_updated_at_microseconds_column();

CREATE TABLE IF NOT EXISTS space_notification_read_markers (
    viewer_space_id TEXT   NOT NULL REFERENCES spaces (space_id) ON DELETE CASCADE,
    friend_space_id TEXT   NOT NULL REFERENCES spaces (space_id) ON DELETE CASCADE,
    read_at        BIGINT NOT NULL DEFAULT 0,
    created_at     BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at     BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    PRIMARY KEY (viewer_space_id, friend_space_id),
    CONSTRAINT chk_space_notification_read_markers_distinct CHECK (viewer_space_id <> friend_space_id)
);

CREATE TRIGGER update_space_notification_read_markers_updated_at
    BEFORE UPDATE ON space_notification_read_markers
    FOR EACH ROW
EXECUTE PROCEDURE trigger_updated_at_microseconds_column();

CREATE TABLE IF NOT EXISTS space_browser_sessions (
    token_hash BYTEA PRIMARY KEY,
    user_id    BIGINT NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    session_wrap_key TEXT   NOT NULL,
    expires_at BIGINT NOT NULL,
    created_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    last_used_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds()
);

CREATE INDEX IF NOT EXISTS idx_space_browser_sessions_user
    ON space_browser_sessions (user_id, last_used_at DESC);

CREATE INDEX IF NOT EXISTS idx_space_browser_sessions_expires
    ON space_browser_sessions (expires_at ASC);

CREATE TRIGGER update_space_browser_sessions_updated_at
    BEFORE UPDATE ON space_browser_sessions
    FOR EACH ROW
EXECUTE PROCEDURE trigger_updated_at_microseconds_column();

CREATE TABLE IF NOT EXISTS space_key_versions (
    space_id             TEXT    NOT NULL REFERENCES spaces (space_id) ON DELETE CASCADE,
    version             INTEGER NOT NULL,
    root_wrapped_space_key BYTEA NOT NULL,
    encrypted_profile   BYTEA   NOT NULL DEFAULT '\x'::bytea,
    wrapped_prev_key    BYTEA,
    created_at          BIGINT  NOT NULL DEFAULT now_utc_micro_seconds(),
    PRIMARY KEY (space_id, version)
);

CREATE INDEX IF NOT EXISTS idx_space_key_versions_space_created
    ON space_key_versions (space_id, created_at DESC);

CREATE TABLE IF NOT EXISTS space_posts (
    post_id              BIGSERIAL PRIMARY KEY,
    space_id              TEXT    NOT NULL REFERENCES spaces (space_id) ON DELETE CASCADE,
    encrypted_post_key   BYTEA   NOT NULL,
    caption_cipher       BYTEA   NOT NULL DEFAULT '\x'::bytea,
    key_version          INTEGER NOT NULL DEFAULT 1,
    is_deleted           BOOLEAN NOT NULL DEFAULT FALSE,
    created_at           BIGINT  NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at           BIGINT  NOT NULL DEFAULT now_utc_micro_seconds()
);

CREATE INDEX IF NOT EXISTS idx_space_posts_space_created
    ON space_posts (space_id, created_at DESC)
    WHERE is_deleted = FALSE;

CREATE TRIGGER update_space_posts_updated_at
    BEFORE UPDATE ON space_posts
    FOR EACH ROW
EXECUTE PROCEDURE trigger_updated_at_microseconds_column();

CREATE TABLE IF NOT EXISTS space_post_assets (
    asset_id             BIGSERIAL PRIMARY KEY,
    post_id              BIGINT NOT NULL REFERENCES space_posts (post_id) ON DELETE CASCADE,
    object_key           TEXT   NOT NULL,
    bucket_id            TEXT   NOT NULL,
    size                 BIGINT,
    position             INTEGER NOT NULL DEFAULT 0,
    metadata_cipher      BYTEA  NOT NULL,
    created_at           BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    CONSTRAINT uq_space_post_assets_object_key UNIQUE (object_key),
    CONSTRAINT chk_space_post_assets_object_key CHECK (object_key <> ''),
    CONSTRAINT chk_space_post_assets_bucket_id CHECK (bucket_id <> ''),
    CONSTRAINT chk_space_post_assets_position CHECK (position >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_space_post_assets_position
    ON space_post_assets (post_id, position);

CREATE INDEX IF NOT EXISTS idx_space_post_assets_post_position
    ON space_post_assets (post_id, position ASC, asset_id ASC);

CREATE TABLE IF NOT EXISTS space_temp_objects (
    object_key      TEXT PRIMARY KEY,
    space_id         TEXT REFERENCES spaces (space_id) ON DELETE CASCADE,
    purpose         TEXT NOT NULL,
    bucket_id       TEXT NOT NULL,
    expected_size   BIGINT NOT NULL,
    expires_at      BIGINT NOT NULL,
    cleanup_after   BIGINT NOT NULL,
    created_at      BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    CONSTRAINT chk_space_temp_objects_purpose CHECK (purpose IN ('post', 'avatar', 'cover')),
    CONSTRAINT chk_space_temp_objects_expected_size CHECK (expected_size > 0)
);

CREATE INDEX IF NOT EXISTS idx_space_temp_objects_expires
    ON space_temp_objects (cleanup_after ASC);

CREATE INDEX IF NOT EXISTS idx_space_temp_objects_active
    ON space_temp_objects (space_id, expires_at)
    WHERE space_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS space_friend_shares (
    space_id              TEXT   NOT NULL REFERENCES spaces (space_id) ON DELETE CASCADE,
    friend_space_id       TEXT   NOT NULL REFERENCES spaces (space_id) ON DELETE CASCADE,
    friend_sealed_space_key BYTEA NOT NULL,
    key_version          INTEGER NOT NULL DEFAULT 1,
    created_at           BIGINT  NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at           BIGINT  NOT NULL DEFAULT now_utc_micro_seconds(),
    PRIMARY KEY (space_id, friend_space_id),
    CONSTRAINT chk_space_friend_shares_distinct CHECK (space_id <> friend_space_id)
);

CREATE INDEX IF NOT EXISTS idx_space_friend_shares_friend_space
    ON space_friend_shares (friend_space_id, created_at DESC);

CREATE TRIGGER update_space_friend_shares_updated_at
    BEFORE UPDATE ON space_friend_shares
    FOR EACH ROW
EXECUTE PROCEDURE trigger_updated_at_microseconds_column();

CREATE TABLE IF NOT EXISTS space_friend_requests (
    request_id                   BIGSERIAL PRIMARY KEY,
    requester_space_id           TEXT   NOT NULL REFERENCES spaces (space_id) ON DELETE CASCADE,
    target_space_id              TEXT   NOT NULL REFERENCES spaces (space_id) ON DELETE CASCADE,
    requester_friend_sealed_space_key BYTEA NOT NULL,
    requester_key_version        INTEGER NOT NULL DEFAULT 1,
    created_at                   BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at                   BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    CONSTRAINT chk_space_friend_requests_distinct_spaces CHECK (requester_space_id <> target_space_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_space_friend_requests_pair
    ON space_friend_requests (requester_space_id, target_space_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_space_friend_requests_unordered_pair
    ON space_friend_requests (
        LEAST(requester_space_id, target_space_id),
        GREATEST(requester_space_id, target_space_id)
    );

CREATE INDEX IF NOT EXISTS idx_space_friend_requests_target_created
    ON space_friend_requests (target_space_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_space_friend_requests_requester_created
    ON space_friend_requests (requester_space_id, created_at DESC);

CREATE TRIGGER update_space_friend_requests_updated_at
    BEFORE UPDATE ON space_friend_requests
    FOR EACH ROW
EXECUTE PROCEDURE trigger_updated_at_microseconds_column();

CREATE OR REPLACE FUNCTION tg_space_messages_null_cipher_on_delete() RETURNS trigger AS $$
BEGIN
    IF NEW.is_deleted THEN
        NEW.message_cipher := NULL;
        NEW.sender_encrypted_message_key := NULL;
        NEW.recipient_encrypted_message_key := NULL;
        NEW.recipient_liked_at := NULL;
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS space_messages (
    message_id                      TEXT PRIMARY KEY,
    sender_space_id                  TEXT   NOT NULL REFERENCES spaces (space_id) ON DELETE CASCADE,
    recipient_space_id               TEXT   NOT NULL REFERENCES spaces (space_id) ON DELETE CASCADE,
    thread_key                      TEXT GENERATED ALWAYS AS (
        CASE
            WHEN sender_space_id < recipient_space_id
                THEN sender_space_id || ':' || recipient_space_id
            ELSE recipient_space_id || ':' || sender_space_id
        END
    ) STORED,
    kind                            TEXT   NOT NULL,
    message_cipher                  BYTEA,
    sender_encrypted_message_key    BYTEA,
    recipient_encrypted_message_key BYTEA,
    reply_post_id                   BIGINT REFERENCES space_posts (post_id) ON DELETE SET NULL,
    reply_message_id                TEXT REFERENCES space_messages (message_id) ON DELETE SET NULL,
    recipient_liked_at              BIGINT,
    is_deleted                      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at                      BIGINT  NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at                      BIGINT  NOT NULL DEFAULT now_utc_micro_seconds(),
    CONSTRAINT chk_space_messages_distinct_spaces CHECK (sender_space_id <> recipient_space_id),
    CONSTRAINT chk_space_messages_kind CHECK (kind IN ('regular', 'post_reply', 'post_like', 'friend_added')),
    CONSTRAINT chk_space_messages_regular_shape CHECK (kind <> 'regular' OR reply_post_id IS NULL),
    CONSTRAINT chk_space_messages_post_reply_shape CHECK (kind <> 'post_reply' OR (reply_post_id IS NOT NULL AND reply_message_id IS NULL)),
    CONSTRAINT chk_space_messages_post_like_shape CHECK (kind <> 'post_like' OR (reply_post_id IS NOT NULL AND reply_message_id IS NULL AND recipient_liked_at IS NULL)),
    CONSTRAINT chk_space_messages_friend_added_shape CHECK (kind <> 'friend_added' OR (reply_post_id IS NULL AND reply_message_id IS NULL AND recipient_liked_at IS NULL)),
    CONSTRAINT chk_space_messages_recipient_like CHECK (
        recipient_liked_at IS NULL OR is_deleted = FALSE
    ),
    CONSTRAINT chk_space_messages_single_reply_target CHECK (reply_post_id IS NULL OR reply_message_id IS NULL),
    CONSTRAINT chk_space_messages_cipher_shape CHECK (
        (
            kind IN ('regular', 'post_reply')
            AND is_deleted = FALSE
            AND message_cipher IS NOT NULL
            AND sender_encrypted_message_key IS NOT NULL
            AND recipient_encrypted_message_key IS NOT NULL
        ) OR (
            kind IN ('regular', 'post_reply')
            AND is_deleted = TRUE
            AND message_cipher IS NULL
            AND sender_encrypted_message_key IS NULL
            AND recipient_encrypted_message_key IS NULL
        ) OR (
            kind IN ('post_like', 'friend_added')
            AND is_deleted = FALSE
            AND message_cipher IS NULL
            AND sender_encrypted_message_key IS NULL
            AND recipient_encrypted_message_key IS NULL
        )
    )
);

CREATE INDEX IF NOT EXISTS idx_space_messages_sender_space_created
    ON space_messages (sender_space_id, created_at DESC, message_id DESC)
    WHERE is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_space_messages_recipient_space_created
    ON space_messages (recipient_space_id, created_at DESC, message_id DESC)
    WHERE is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_space_messages_thread_created
    ON space_messages (thread_key, created_at DESC, message_id DESC);

CREATE INDEX IF NOT EXISTS idx_space_messages_reply_post
    ON space_messages (reply_post_id)
    WHERE reply_post_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_space_messages_post_like
    ON space_messages (reply_post_id, sender_space_id)
    WHERE kind = 'post_like';

CREATE INDEX IF NOT EXISTS idx_space_messages_reply_message
    ON space_messages (reply_message_id)
    WHERE reply_message_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_space_messages_sender_liked
    ON space_messages (sender_space_id, recipient_liked_at DESC, message_id DESC)
    WHERE recipient_liked_at IS NOT NULL AND is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_space_messages_recipient_liked
    ON space_messages (recipient_space_id, recipient_liked_at DESC, message_id DESC)
    WHERE recipient_liked_at IS NOT NULL AND is_deleted = FALSE;

CREATE TRIGGER space_messages_null_cipher_on_delete
    BEFORE INSERT OR UPDATE ON space_messages
    FOR EACH ROW
EXECUTE PROCEDURE tg_space_messages_null_cipher_on_delete();

CREATE TRIGGER update_space_messages_updated_at
    BEFORE UPDATE ON space_messages
    FOR EACH ROW
EXECUTE PROCEDURE trigger_updated_at_microseconds_column();
