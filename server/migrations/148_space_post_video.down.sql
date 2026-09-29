DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM space_post_assets WHERE role = 'video') THEN
        RAISE EXCEPTION 'Cannot roll back while video posts exist';
    END IF;
END $$;
DROP INDEX uq_space_posts_client_request;
ALTER TABLE space_posts DROP COLUMN client_request_id;
DROP INDEX uq_space_post_assets_position;
ALTER TABLE space_post_assets DROP COLUMN role;
CREATE UNIQUE INDEX uq_space_post_assets_position ON space_post_assets (post_id, position);
