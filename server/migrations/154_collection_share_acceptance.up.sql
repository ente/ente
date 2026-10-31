ALTER TABLE collection_shares
    ADD COLUMN acceptance_status TEXT NOT NULL DEFAULT 'accepted'
        CHECK (acceptance_status IN ('pending', 'accepted', 'rejected')),
    ADD COLUMN invited_by_user_id BIGINT;

CREATE INDEX collection_shares_pending_inviter_recipient_index
    ON collection_shares (invited_by_user_id, to_user_id)
    WHERE is_deleted = FALSE AND acceptance_status = 'pending';
