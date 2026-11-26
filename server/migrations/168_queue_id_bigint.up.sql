DO $$
DECLARE
    seq_name TEXT;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_attribute a
        WHERE a.attrelid = 'queue'::regclass
          AND a.attname = 'queue_id'
          AND NOT a.attisdropped
          AND a.atttypid <> 'bigint'::regtype
    ) THEN
        ALTER TABLE queue ALTER COLUMN queue_id TYPE BIGINT;
    END IF;

    seq_name := pg_get_serial_sequence('queue', 'queue_id');
    IF seq_name IS NOT NULL AND EXISTS (
        SELECT 1
        FROM pg_catalog.pg_sequence s
        WHERE s.seqrelid = seq_name::regclass
          AND s.seqtypid <> 'bigint'::regtype
    ) THEN
        EXECUTE format('ALTER SEQUENCE %s AS BIGINT NO MAXVALUE', seq_name);
    END IF;
END
$$;
