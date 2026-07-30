CREATE TABLE IF NOT EXISTS space_links (
    link_id               BIGSERIAL PRIMARY KEY,
    space_id              TEXT    NOT NULL REFERENCES spaces (space_id) ON DELETE CASCADE,
    auth_key_hash         BYTEA   NOT NULL UNIQUE,
    kdf_salt              BYTEA   NOT NULL,
    kdf_mem_limit         BIGINT  NOT NULL,
    kdf_ops_limit         BIGINT  NOT NULL,
    key_version           INTEGER NOT NULL,
    encrypted_space_key   BYTEA   NOT NULL,
    encrypted_access_key  BYTEA   NOT NULL,
    active                BOOLEAN NOT NULL DEFAULT TRUE,
    created_at            BIGINT  NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at            BIGINT  NOT NULL DEFAULT now_utc_micro_seconds(),
    CONSTRAINT chk_space_links_auth_key_hash CHECK (octet_length(auth_key_hash) = 32),
    CONSTRAINT chk_space_links_kdf_salt CHECK (octet_length(kdf_salt) = 16),
    CONSTRAINT chk_space_links_kdf_mem_limit CHECK (kdf_mem_limit = 67108864),
    CONSTRAINT chk_space_links_kdf_ops_limit CHECK (kdf_ops_limit = 2),
    CONSTRAINT chk_space_links_key_version CHECK (key_version > 0),
    CONSTRAINT chk_space_links_encrypted_space_key CHECK (octet_length(encrypted_space_key) > 0),
    CONSTRAINT chk_space_links_encrypted_access_key CHECK (octet_length(encrypted_access_key) > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_space_links_active_space
    ON space_links (space_id)
    WHERE active = TRUE;

CREATE INDEX IF NOT EXISTS idx_space_links_space_created
    ON space_links (space_id, created_at DESC);

CREATE TRIGGER update_space_links_updated_at
    BEFORE UPDATE ON space_links
    FOR EACH ROW
EXECUTE PROCEDURE trigger_updated_at_microseconds_column();
