ALTER TABLE users
    ADD COLUMN IF NOT EXISTS source text;
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS delete_feedback jsonb;
