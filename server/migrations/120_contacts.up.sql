CREATE TABLE IF NOT EXISTS contact_entity
(
    id                            TEXT    PRIMARY KEY NOT NULL,
    user_id                       BIGINT  NOT NULL,
    contact_user_id               BIGINT  NOT NULL,
    profile_picture_attachment_id TEXT,
    encrypted_key                 BYTEA   NOT NULL,
    encrypted_data                BYTEA,
    is_deleted                    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at                    BIGINT  NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at                    BIGINT  NOT NULL DEFAULT now_utc_micro_seconds(),
    CONSTRAINT fk_contact_entity_user_id FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE,
    CONSTRAINT contact_entity_state_constraint CHECK (
        (is_deleted = FALSE AND encrypted_data IS NOT NULL) OR
        (is_deleted = TRUE AND encrypted_data IS NULL AND profile_picture_attachment_id IS NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_contact_entity_user_updated_at
    ON contact_entity (user_id, updated_at);

CREATE UNIQUE INDEX IF NOT EXISTS idx_contact_entity_user_contact_user_id
    ON contact_entity (user_id, contact_user_id);

CREATE OR REPLACE FUNCTION fn_reject_contact_key_update()
RETURNS TRIGGER AS
$$
BEGIN
    IF NEW.encrypted_key IS DISTINCT FROM OLD.encrypted_key THEN
        RAISE EXCEPTION 'contact_entity.encrypted_key is immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_reject_contact_key_update
    BEFORE UPDATE
    ON contact_entity
    FOR EACH ROW
EXECUTE FUNCTION fn_reject_contact_key_update();

CREATE TRIGGER update_contact_entity_updated_at
    BEFORE UPDATE
    ON contact_entity
    FOR EACH ROW
EXECUTE PROCEDURE trigger_updated_at_microseconds_column();

CREATE TABLE IF NOT EXISTS user_attachments
(
    attachment_id         TEXT       PRIMARY KEY NOT NULL,
    user_id               BIGINT     NOT NULL,
    attachment_type       TEXT       NOT NULL,
    size                  BIGINT     NOT NULL,
    latest_bucket         s3region   NOT NULL,
    replicated_buckets    s3region[] NOT NULL DEFAULT '{}',
    delete_from_buckets   s3region[] NOT NULL DEFAULT '{}',
    inflight_rep_buckets  s3region[] NOT NULL DEFAULT '{}',
    is_deleted            BOOLEAN    NOT NULL DEFAULT FALSE,
    pending_sync          BOOLEAN    NOT NULL DEFAULT TRUE,
    sync_locked_till      BIGINT     NOT NULL DEFAULT 0,
    created_at            BIGINT     NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at            BIGINT     NOT NULL DEFAULT now_utc_micro_seconds(),
    CONSTRAINT fk_user_attachments_user_id FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_user_attachments_pending_sync_locked_till
    ON user_attachments (is_deleted, sync_locked_till)
    WHERE pending_sync = TRUE;

CREATE INDEX IF NOT EXISTS idx_user_attachments_lookup
    ON user_attachments (user_id, attachment_type, is_deleted);

CREATE OR REPLACE FUNCTION ensure_no_common_attachment_buckets()
RETURNS TRIGGER AS
$$
DECLARE
    all_buckets       s3region[];
    duplicate_buckets s3region[];
BEGIN
    all_buckets := ARRAY [NEW.latest_bucket]
                   || NEW.replicated_buckets
                   || NEW.delete_from_buckets
                   || NEW.inflight_rep_buckets;

    SELECT ARRAY_AGG(DISTINCT bucket)
      INTO duplicate_buckets
      FROM unnest(all_buckets) bucket
     GROUP BY bucket
    HAVING COUNT(*) > 1;

    IF ARRAY_LENGTH(duplicate_buckets, 1) > 0 THEN
        RAISE EXCEPTION 'Duplicate bucket IDs found in attachment row: %', duplicate_buckets;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_no_common_attachment_buckets
    BEFORE INSERT OR UPDATE
    ON user_attachments
    FOR EACH ROW
EXECUTE FUNCTION ensure_no_common_attachment_buckets();

CREATE TRIGGER update_user_attachments_updated_at
    BEFORE UPDATE
    ON user_attachments
    FOR EACH ROW
EXECUTE PROCEDURE trigger_updated_at_microseconds_column();
