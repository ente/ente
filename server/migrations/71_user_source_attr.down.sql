ALTER TABLE users
    DROP COLUMN IF EXISTS source;
ALTER TABLE users
    DROP COLUMN IF EXISTS delete_feedback;
