DROP TRIGGER IF EXISTS update_user_attachments_updated_at ON user_attachments;
DROP TRIGGER IF EXISTS check_no_common_attachment_buckets ON user_attachments;
DROP FUNCTION IF EXISTS ensure_no_common_attachment_buckets();
DROP TABLE IF EXISTS user_attachments;

DROP TRIGGER IF EXISTS update_contact_entity_updated_at ON contact_entity;
DROP TRIGGER IF EXISTS trigger_reject_contact_key_update ON contact_entity;
DROP FUNCTION IF EXISTS fn_reject_contact_key_update();
DROP TABLE IF EXISTS contact_entity;
