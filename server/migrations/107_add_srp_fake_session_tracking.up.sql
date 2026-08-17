-- Add is_fake column to track fake sessions for user enumeration protection
ALTER TABLE srp_sessions
ADD COLUMN IF NOT EXISTS is_fake BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_srp_sessions_fake_created
ON srp_sessions(is_fake, created_at)
WHERE is_fake = true;
