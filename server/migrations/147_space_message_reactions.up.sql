ALTER TABLE space_messages
    ADD COLUMN recipient_reaction_cipher BYTEA,
    ADD COLUMN sender_encrypted_reaction_key BYTEA,
    ADD COLUMN recipient_encrypted_reaction_key BYTEA,
    ADD COLUMN recipient_reacted_at BIGINT;

ALTER TABLE space_messages
    ADD CONSTRAINT chk_space_messages_reaction_shape CHECK (
        (recipient_reaction_cipher IS NULL
            AND sender_encrypted_reaction_key IS NULL
            AND recipient_encrypted_reaction_key IS NULL
            AND recipient_reacted_at IS NULL)
        OR (recipient_reaction_cipher IS NOT NULL
            AND sender_encrypted_reaction_key IS NOT NULL
            AND recipient_encrypted_reaction_key IS NOT NULL
            AND recipient_reacted_at IS NOT NULL
            AND recipient_liked_at IS NULL
            AND kind IN ('regular', 'post_reply')
            AND is_deleted = FALSE)
    );

CREATE INDEX idx_space_messages_sender_reacted
    ON space_messages (sender_space_id, recipient_reacted_at DESC, message_id DESC)
    WHERE recipient_reacted_at IS NOT NULL AND is_deleted = FALSE;

CREATE OR REPLACE FUNCTION tg_space_messages_null_cipher_on_delete() RETURNS trigger AS $$
BEGIN
    IF NEW.is_deleted THEN
        NEW.message_cipher := NULL;
        NEW.sender_encrypted_message_key := NULL;
        NEW.recipient_encrypted_message_key := NULL;
        NEW.recipient_liked_at := NULL;
        NEW.recipient_reaction_cipher := NULL;
        NEW.sender_encrypted_reaction_key := NULL;
        NEW.recipient_encrypted_reaction_key := NULL;
        NEW.recipient_reacted_at := NULL;
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
