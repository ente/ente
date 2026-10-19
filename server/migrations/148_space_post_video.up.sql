ALTER TABLE space_post_assets ADD COLUMN role TEXT NOT NULL DEFAULT 'preview';
ALTER TABLE space_post_assets ADD CONSTRAINT chk_space_post_assets_role CHECK (role IN ('preview', 'video'));
DROP INDEX uq_space_post_assets_position;
CREATE UNIQUE INDEX uq_space_post_assets_position ON space_post_assets (post_id, position, role);
ALTER TABLE space_posts ADD COLUMN client_request_id TEXT;
CREATE UNIQUE INDEX uq_space_posts_client_request ON space_posts (space_id, client_request_id) WHERE client_request_id IS NOT NULL;
