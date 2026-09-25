DROP INDEX IF EXISTS idx_space_messages_sender_reacted;

ALTER TABLE space_messages
    DROP CONSTRAINT chk_space_messages_reaction_shape,
    DROP COLUMN recipient_reaction_cipher,
    DROP COLUMN sender_encrypted_reaction_key,
    DROP COLUMN recipient_encrypted_reaction_key,
    DROP COLUMN recipient_reacted_at;

CREATE OR REPLACE FUNCTION tg_space_messages_null_cipher_on_delete() RETURNS trigger AS $$
BEGIN
    IF NEW.is_deleted THEN
        NEW.message_cipher := NULL;
        NEW.sender_encrypted_message_key := NULL;
        NEW.recipient_encrypted_message_key := NULL;
        NEW.recipient_liked_at := NULL;
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
