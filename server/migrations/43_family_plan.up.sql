ALTER TABLE users
    ADD COLUMN family_admin_id BIGINT;

CREATE TABLE IF NOT EXISTS families
(
    id         uuid PRIMARY KEY NOT NULL,
    admin_id   BIGINT           NOT NULL,
    member_id  BIGINT           NOT NULL,
--  status indicates the member status
-- SELF/CLOSED are the state of the admin member when they create a family group or close it.

    status     TEXT             NOT NULL CHECK (status IN
                                                ('SELF', 'CLOSED', 'INVITED', 'ACCEPTED', 'DECLINED', 'REVOKED', 'REMOVED',
                                                 'LEFT')),
    token      TEXT             UNIQUE,
    percentage INTEGER          NOT NULL DEFAULT -1,
    created_at bigint           NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at bigint           NOT NULL DEFAULT now_utc_micro_seconds(),
    CONSTRAINT fk_family_admin_id
        FOREIGN KEY (admin_id)
            REFERENCES users (user_id)
            ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS fk_families_admin_id ON families (admin_id);

CREATE UNIQUE INDEX uidx_one_family_check on families (member_id, status) where status in ('ACCEPTED', 'SELF');

CREATE UNIQUE INDEX uidx_families_member_mapping on families (admin_id, member_id);

ALTER TABLE families
    ADD CONSTRAINT families_member_state_constraint CHECK (
        (admin_id != member_id and status not in ('SELF','CLOSED') or (admin_id = member_id and status in ('SELF', 'CLOSED'))));


CREATE TRIGGER update_families_updated_at
    BEFORE UPDATE
    ON families
    FOR EACH ROW
EXECUTE PROCEDURE
    trigger_updated_at_microseconds_column();
