DROP INDEX collection_shares_pending_inviter_recipient_index;

ALTER TABLE collection_shares
    DROP COLUMN invited_by_user_id,
    DROP COLUMN acceptance_status;
