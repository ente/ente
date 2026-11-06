CREATE INDEX CONCURRENTLY object_copies_b2_null_index
    ON object_copies (b2) WHERE b2 IS NULL AND want_b2 = true;
