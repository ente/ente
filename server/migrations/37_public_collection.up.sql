CREATE TABLE IF NOT EXISTS public_collection_tokens
(
    id            bigint primary key generated always as identity,
    collection_id BIGINT NOT NULL,
    access_token  TEXT   NOT NULL,
    is_disabled   bool   not null DEFAULT FALSE,
    --     0 value for valid_till indicates that the link never expires.
    valid_till    bigint not null DEFAULT 0,
    -- 0 device limit indicates no limit
    device_limit  int    not null DEFAULT 0,
    created_at    bigint NOT NULL DEFAULT now_utc_micro_seconds(),
    updated_at    bigint NOT NULL DEFAULT now_utc_micro_seconds(),
    CONSTRAINT fk_public_tokens_collection_id
        FOREIGN KEY (collection_id)
            REFERENCES collections (collection_id)
            ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS public_active_collection_unique_idx ON public_collection_tokens (collection_id, is_disabled) WHERE is_disabled = FALSE;
CREATE UNIQUE INDEX IF NOT EXISTS public_access_tokens_unique_idx ON public_collection_tokens (access_token);

CREATE TABLE IF NOT EXISTS public_collection_access_history
(
    share_id   bigint,
    ip         text   not null,
    user_agent text   not null,
    created_at bigint NOT NULL DEFAULT now_utc_micro_seconds(),
    CONSTRAINT unique_access_sid_ip_ua UNIQUE (share_id, ip, user_agent),
    CONSTRAINT fk_public_history_token_id
        FOREIGN KEY (share_id)
            REFERENCES public_collection_tokens (id)
            ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS public_access_share_id_idx ON public_collection_access_history (share_id);

CREATE TABLE IF NOT EXISTS public_abuse_report
(
    share_id   bigint,
    ip         text           not null,
    user_agent text           not null,
    url        text           not null,
    reason     text           not null,
    u_comment  varchar(10000) not null DEFAULT '',
    created_at bigint         NOT NULL DEFAULT now_utc_micro_seconds(),
    CONSTRAINT unique_report_sid_ip_ua UNIQUE (share_id, ip, user_agent),
    CONSTRAINT fk_public_abuse_report_token_id
        FOREIGN KEY (share_id)
            REFERENCES public_collection_tokens (id)
            ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS public_abuse_share_id_idx ON public_abuse_report (share_id);

CREATE TRIGGER update_public_collection_tokens_updated_at
    BEFORE UPDATE
    ON public_collection_tokens
    FOR EACH ROW
EXECUTE PROCEDURE
    trigger_updated_at_microseconds_column();

CREATE OR REPLACE FUNCTION fn_update_collections_updation_time_using_update_at() RETURNS TRIGGER AS $$
BEGIN
    IF  (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
        UPDATE collections SET updation_time = NEW.updated_at where collection_id = new.collection_id and
                updation_time < New.updated_at;
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_collection_updation_time_on_collection_tokens_updated
    AFTER INSERT OR UPDATE
    ON public_collection_tokens
    FOR EACH ROW
EXECUTE PROCEDURE
    fn_update_collections_updation_time_using_update_at();