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

ALTER TABLE space_messages
    DROP CONSTRAINT chk_space_messages_reaction,
    DROP COLUMN sender_encrypted_reaction,
    DROP COLUMN recipient_encrypted_reaction;
