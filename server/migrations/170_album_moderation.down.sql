ALTER TABLE collection_files
    DROP COLUMN moderation_status,
    DROP COLUMN anon_user_id;

ALTER TABLE public_collection_tokens DROP COLUMN require_approval;

DROP TYPE collection_file_moderation;
