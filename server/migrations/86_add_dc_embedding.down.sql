ALTER TABLE embeddings DROP COLUMN IF EXISTS datacenters;

DO
$$
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_embeddings_updated_at') THEN
            CREATE TRIGGER update_embeddings_updated_at
                BEFORE UPDATE
                ON embeddings
                FOR EACH ROW
            EXECUTE PROCEDURE
                trigger_updated_at_microseconds_column();
        ELSE
            RAISE NOTICE 'Trigger update_embeddings_updated_at already exists.';
        END IF;
    END
$$;