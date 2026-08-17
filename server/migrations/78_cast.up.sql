-- note: using casting as table name because cast is a reserved word in postgres
CREATE  TABLE IF NOT EXISTS casting
(
    id uuid not null primary key,
    code VARCHAR(16) NOT NULL,
    public_key VARCHAR(512) NOT NULL,
    collection_id BIGINT,
    cast_user BIGINT,
    encrypted_payload text,
    token VARCHAR(512),
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
    last_used_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds()
);
CREATE UNIQUE INDEX IF NOT EXISTS casting_code_unique_idx ON casting (code) WHERE is_deleted = FALSE;
