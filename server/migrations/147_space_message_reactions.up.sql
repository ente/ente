ALTER TABLE space_messages
    ADD COLUMN sender_encrypted_reaction BYTEA,
    ADD COLUMN recipient_encrypted_reaction BYTEA,
    ADD CONSTRAINT chk_space_messages_reaction CHECK (
        (sender_encrypted_reaction IS NULL AND recipient_encrypted_reaction IS NULL)
        OR (
            sender_encrypted_reaction IS NOT NULL
            AND recipient_encrypted_reaction IS NOT NULL
            AND octet_length(sender_encrypted_reaction) = 304
            AND octet_length(recipient_encrypted_reaction) = 304
            AND recipient_liked_at IS NOT NULL
            AND kind IN ('regular', 'post_reply')
            AND is_deleted = FALSE
        )
    );

CREATE OR REPLACE FUNCTION tg_space_messages_null_cipher_on_delete() RETURNS trigger AS $$
BEGIN
    IF NEW.is_deleted THEN
        NEW.message_cipher := NULL;
        NEW.sender_encrypted_message_key := NULL;
        NEW.recipient_encrypted_message_key := NULL;
        NEW.recipient_liked_at := NULL;
        NEW.sender_encrypted_reaction := NULL;
        NEW.recipient_encrypted_reaction := NULL;
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
