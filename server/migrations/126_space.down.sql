DROP TRIGGER IF EXISTS update_space_friend_requests_updated_at ON space_friend_requests;
DROP TABLE IF EXISTS space_friend_requests;

DROP TRIGGER IF EXISTS update_space_friend_shares_updated_at ON space_friend_shares;
DROP TABLE IF EXISTS space_friend_shares;

DROP TRIGGER IF EXISTS update_space_messages_updated_at ON space_messages;
DROP TRIGGER IF EXISTS space_messages_null_cipher_on_delete ON space_messages;
DROP TABLE IF EXISTS space_messages;
DROP FUNCTION IF EXISTS tg_space_messages_null_cipher_on_delete();

DROP TABLE IF EXISTS space_temp_objects;
DROP TABLE IF EXISTS space_post_assets;

DROP TRIGGER IF EXISTS update_space_posts_updated_at ON space_posts;
DROP TABLE IF EXISTS space_posts;

DROP TABLE IF EXISTS space_key_versions;

DROP TRIGGER IF EXISTS update_space_browser_sessions_updated_at ON space_browser_sessions;
DROP TABLE IF EXISTS space_browser_sessions;

DROP TRIGGER IF EXISTS update_space_notification_read_markers_updated_at ON space_notification_read_markers;
DROP TABLE IF EXISTS space_notification_read_markers;

DROP TRIGGER IF EXISTS update_space_profile_assets_updated_at ON space_profile_assets;
DROP TABLE IF EXISTS space_profile_assets;

DROP TRIGGER IF EXISTS update_spaces_updated_at ON spaces;
DROP TABLE IF EXISTS spaces;
