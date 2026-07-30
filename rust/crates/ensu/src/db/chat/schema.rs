pub(super) const CREATE_INDEXES: &str = "
CREATE INDEX IF NOT EXISTS idx_messages_order ON messages(session_uuid, created_at, message_uuid);
CREATE INDEX IF NOT EXISTS idx_sessions_updated ON sessions(updated_at);
";

pub(super) const CREATE_ALL: &str = "
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS sessions (
  session_uuid TEXT PRIMARY KEY NOT NULL,
  title        BLOB NOT NULL,
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS messages (
  message_uuid        TEXT PRIMARY KEY NOT NULL,
  session_uuid        TEXT NOT NULL,
  parent_message_uuid TEXT,
  sender              TEXT NOT NULL CHECK(sender IN ('self','other')),
  text                BLOB NOT NULL,
  attachments         TEXT,
  created_at          INTEGER NOT NULL,
  FOREIGN KEY (session_uuid) REFERENCES sessions(session_uuid) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_messages_order ON messages(session_uuid, created_at, message_uuid);
CREATE INDEX IF NOT EXISTS idx_sessions_updated ON sessions(updated_at);
";
