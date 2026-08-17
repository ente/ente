CREATE TABLE IF NOT EXISTS emergency_contact (
                                                 user_id BIGINT NOT NULL,
                                                 emergency_contact_id BIGINT NOT NULL,
                                                 state TEXT NOT NULL CHECK (state IN ('INVITED', 'ACCEPTED', 'REVOKED', 'DELETED', 'CONTACT_LEFT', 'CONTACT_DENIED')),
                                                 created_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
                                                 updated_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
                                                 notice_period_in_hrs INT NOT NULL,
                                                 encrypted_key TEXT,
                                                 CONSTRAINT fk_emergency_contact_user_id
                                                     FOREIGN KEY (user_id)
                                                         REFERENCES users (user_id)
                                                         ON DELETE CASCADE,
                                                 CONSTRAINT fk_emergency_contact_emergency_contact_id
                                                     FOREIGN KEY (emergency_contact_id)
                                                         REFERENCES users (user_id)
                                                         ON DELETE CASCADE,
                                                 CONSTRAINT chk_user_id_not_equal_emergency_contact_id
                                                     CHECK (user_id != emergency_contact_id),
                                                 CONSTRAINT chk_encrypted_key_null
                                                     CHECK ((state IN ('REVOKED', 'DELETED', 'CONTACT_LEFT', 'CONTACT_DENIED') AND encrypted_key IS NULL) OR
                                                            (state NOT IN ('REVOKED', 'DELETED', 'CONTACT_LEFT', 'CONTACT_DENIED') AND encrypted_key IS NOT NULL)),
                                                 CONSTRAINT unique_user_emergency_contact
                                                     UNIQUE (user_id, emergency_contact_id)
);

CREATE INDEX idx_emergency_contact_id ON emergency_contact(emergency_contact_id);


CREATE TRIGGER update_emergency_conctact_updated_at
    BEFORE UPDATE
    ON families
    FOR EACH ROW
EXECUTE PROCEDURE
    trigger_updated_at_microseconds_column();


CREATE TABLE IF NOT EXISTS emergency_recovery (
                                                  id uuid PRIMARY KEY NOT NULL,
                                                  user_id BIGINT NOT NULL,
                                                  emergency_contact_id BIGINT NOT NULL,
                                                  status TEXT NOT NULL CHECK (status IN ('WAITING', 'REJECTED', 'RECOVERED', 'STOPPED', 'READY')),
                                                  wait_till BIGINT,
                                                  next_reminder_at BIGINT,
                                                  created_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
                                                  updated_at BIGINT NOT NULL DEFAULT now_utc_micro_seconds(),
                                                  CONSTRAINT fk_emergency_recovery_user_id
                                                      FOREIGN KEY (user_id)
                                                          REFERENCES users (user_id)
                                                          ON DELETE CASCADE,
                                                  CONSTRAINT fk_emergency_recovery_emergency_contact_id
                                                      FOREIGN KEY (emergency_contact_id)
                                                          REFERENCES users (user_id)
                                                          ON DELETE CASCADE
);

CREATE UNIQUE INDEX idx_emergency_recovery_limit_active_recovery ON emergency_recovery(user_id, emergency_contact_id, status)
    WHERE status IN ('WAITING', 'READY');

CREATE INDEX idx_emergency_recovery_user_id ON emergency_recovery(user_id);
CREATE INDEX idx_emergency_recovery_next_reminder_at ON emergency_recovery(next_reminder_at);

CREATE TRIGGER update_emergency_recovery_updated_at
    BEFORE UPDATE
    ON families
    FOR EACH ROW
EXECUTE PROCEDURE
    trigger_updated_at_microseconds_column();