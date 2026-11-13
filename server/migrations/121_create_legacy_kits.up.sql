CREATE TABLE IF NOT EXISTS legacy_kit (
    id UUID PRIMARY KEY NOT NULL,
    user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    -- Closed numeric scheme identifier. 1 = 2-of-3 shares.
    variant INT NOT NULL CHECK (variant IN (1)),
    notice_period_in_hrs INT NOT NULL,
    -- Base64(secretbox nonce || MAC || ciphertext) of the user's recovery key.
    encrypted_recovery_blob TEXT NOT NULL,
    -- Base64(X25519 public key) derived deterministically from the kit secret.
    auth_public_key TEXT NOT NULL,
    -- Base64(secretbox nonce || MAC || ciphertext) of owner-only part names and
    -- stored share payloads used for listing and downloading cards again.
    encrypted_owner_blob TEXT NOT NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    deleted_at BIGINT
);

CREATE INDEX IF NOT EXISTS idx_legacy_kit_user_id ON legacy_kit(user_id);
CREATE INDEX IF NOT EXISTS idx_legacy_kit_active_user_id ON legacy_kit(user_id) WHERE is_deleted = FALSE;

CREATE TRIGGER update_legacy_kit_updated_at
    BEFORE UPDATE
    ON legacy_kit
    FOR EACH ROW
EXECUTE PROCEDURE
    trigger_updated_at_microseconds_column();

CREATE TABLE IF NOT EXISTS legacy_kit_challenge (
    id UUID PRIMARY KEY NOT NULL,
    -- Multiple in-flight challenges can exist for the same kit so one client
    -- requesting a fresh challenge does not invalidate another client's pending
    -- proof-of-possession attempt.
    kit_id UUID NOT NULL REFERENCES legacy_kit(id) ON DELETE CASCADE,
    -- Base64url(SHA-256(challenge)). The server never needs to persist the
    -- plaintext challenge because recovery-open can compare against the hash.
    challenge_hash TEXT NOT NULL,
    expires_at BIGINT NOT NULL,
    created_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds()
);

CREATE INDEX IF NOT EXISTS idx_legacy_kit_challenge_kit_id ON legacy_kit_challenge(kit_id);
CREATE INDEX IF NOT EXISTS idx_legacy_kit_challenge_expires_at ON legacy_kit_challenge(expires_at);

CREATE TABLE IF NOT EXISTS legacy_kit_recovery_session (
    id UUID PRIMARY KEY NOT NULL,
    kit_id UUID NOT NULL REFERENCES legacy_kit(id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    status TEXT NOT NULL CHECK (status IN ('WAITING', 'READY', 'BLOCKED', 'CANCELLED', 'RECOVERED')),
    effective_notice_period_in_hrs INT NOT NULL,
    wait_till BIGINT NOT NULL,
    next_reminder_at BIGINT,
    -- Append-only audit hints for successful recovery-open calls. Each entry is
    -- a JSON object with client-reported usedPartIndexes and server-captured
    -- ip/userAgent for that browser or tab.
    initiators JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_legacy_kit_recovery_active_per_kit
    ON legacy_kit_recovery_session(kit_id)
    WHERE status IN ('WAITING', 'READY');

CREATE INDEX IF NOT EXISTS idx_legacy_kit_recovery_user_id ON legacy_kit_recovery_session(user_id);
CREATE INDEX IF NOT EXISTS idx_legacy_kit_recovery_kit_id ON legacy_kit_recovery_session(kit_id);

CREATE TRIGGER update_legacy_kit_recovery_session_updated_at
    BEFORE UPDATE
    ON legacy_kit_recovery_session
    FOR EACH ROW
EXECUTE PROCEDURE
    trigger_updated_at_microseconds_column();

CREATE TABLE IF NOT EXISTS legacy_kit_recovery_session_token (
    id UUID PRIMARY KEY NOT NULL,
    session_id UUID NOT NULL REFERENCES legacy_kit_recovery_session(id) ON DELETE CASCADE,
    -- Base64url(SHA-256(raw session token)). Each browser/tab gets its own raw
    -- token while the server stores only hashed token material.
    token_hash TEXT NOT NULL UNIQUE,
    created_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds()
);

CREATE INDEX IF NOT EXISTS idx_legacy_kit_recovery_session_token_session_id
    ON legacy_kit_recovery_session_token(session_id);
