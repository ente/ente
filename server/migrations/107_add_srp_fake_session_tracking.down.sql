DROP INDEX IF EXISTS idx_srp_sessions_fake_created;
ALTER TABLE srp_sessions DROP COLUMN IF EXISTS is_fake;
