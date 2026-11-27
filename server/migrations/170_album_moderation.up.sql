CREATE TYPE collection_file_moderation AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'REMOVED');

ALTER TABLE collection_files
    ADD COLUMN moderation_status collection_file_moderation,
    ADD COLUMN anon_user_id TEXT;

ALTER TABLE public_collection_tokens ADD COLUMN require_approval BOOLEAN NOT NULL DEFAULT FALSE;
