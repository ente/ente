ALTER TABLE temp_objects ADD COLUMN IF NOT EXISTS bucket_id s3region;
ALTER TYPE OBJECT_TYPE ADD VALUE 'mldata';
ALTER TYPE s3region ADD VALUE 'b5';
ALTER TYPE s3region ADD VALUE 'b6';
CREATE TABLE IF NOT EXISTS file_data
(
    file_id              BIGINT      NOT NULL,
    user_id              BIGINT      NOT NULL,
    data_type            OBJECT_TYPE NOT NULL,
    size                 BIGINT      NOT NULL,
    latest_bucket        s3region    NOT NULL,
    replicated_buckets   s3region[]  NOT NULL DEFAULT '{}',
--  following field contains list of buckets from where we need to delete the data as the given data_type will not longer be persisted in that dc
    delete_from_buckets  s3region[]  NOT NULL DEFAULT '{}',
    inflight_rep_buckets s3region[]  NOT NULL DEFAULT '{}',
    is_deleted           BOOLEAN     NOT NULL DEFAULT false,
    pending_sync         BOOLEAN     NOT NULL DEFAULT true,
    sync_locked_till     BIGINT      NOT NULL DEFAULT 0,
    created_at           BIGINT      NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at           BIGINT      NOT NULL DEFAULT now_utc_micro_seconds(),
    PRIMARY KEY (file_id, data_type)
);

CREATE INDEX idx_file_data_user_type_deleted ON file_data (user_id, data_type, is_deleted) INCLUDE (size);
CREATE INDEX idx_file_data_pending_sync_locked_till ON file_data (is_deleted, sync_locked_till) where pending_sync = true;

CREATE OR REPLACE FUNCTION ensure_no_common_entries()
    RETURNS TRIGGER AS
$$
DECLARE
    all_buckets       s3region[];
    duplicate_buckets s3region[];
BEGIN
    all_buckets := ARRAY [NEW.latest_bucket] || NEW.replicated_buckets || NEW.delete_from_buckets ||
                   NEW.inflight_rep_buckets;

    SELECT ARRAY_AGG(DISTINCT bucket)
    INTO duplicate_buckets
    FROM unnest(all_buckets) bucket
    GROUP BY bucket
    HAVING COUNT(*) > 1;

    IF ARRAY_LENGTH(duplicate_buckets, 1) > 0 THEN
        RAISE EXCEPTION 'Duplicate bucket IDs found: %. Latest: %, Replicated: %, To Delete: %, Inflight: %',
            duplicate_buckets, NEW.latest_bucket, NEW.replicated_buckets, NEW.delete_from_buckets, NEW.inflight_rep_buckets;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_no_common_entries
    BEFORE INSERT OR UPDATE
    ON file_data
    FOR EACH ROW
EXECUTE FUNCTION ensure_no_common_entries();
