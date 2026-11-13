CREATE TABLE IF NOT EXISTS object_copies (
    object_key   TEXT PRIMARY KEY,
    b2           BIGINT,
    want_b2      BOOLEAN,
    wasabi       BIGINT,
    want_wasabi  BOOLEAN,
    scw          BIGINT,
    want_scw     BOOLEAN,
    last_attempt BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT fk_object_copies_object_key FOREIGN KEY (object_key)
        REFERENCES object_keys (object_key) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS object_copies_wasabi_null_index
ON object_copies (wasabi) WHERE wasabi IS NULL AND want_wasabi = true;

CREATE INDEX IF NOT EXISTS object_copies_scw_null_index
ON object_copies (scw) WHERE scw IS NULL AND want_scw = true;

-- object_copies serves a queue for which all objects still need to be
-- replicated. However, the canonical source of truth for an object is still
-- maintained in the original object_keys table.
ALTER TYPE s3region ADD VALUE 'wasabi-eu-central-2-v3';
ALTER TYPE s3region ADD VALUE 'scw-eu-fr-v3';
