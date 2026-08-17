CREATE TABLE
    IF NOT EXISTS passkeys(
        id uuid PRIMARY KEY NOT NULL,
        user_id BIGINT NOT NULL,
        friendly_name TEXT NOT NULL,
        deleted_at BIGINT,
        created_at bigint NOT NULL DEFAULT now_utc_micro_seconds(),

CONSTRAINT fk_passkeys_user_id FOREIGN KEY(user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE TABLE
    IF NOT EXISTS passkey_credentials(
        passkey_id uuid PRIMARY KEY NOT NULL,

        credential_id TEXT NOT NULL UNIQUE,

-- []byte data will be encoded in b64 before being inserted into the DB

-- fields that are are arrays will be comma separated strings

-- structs will be encoded into JSON before being inserted into DB (they don't need to be queried anyway)

public_key TEXT NOT NULL,
attestation_type TEXT NOT NULL,
authenticator_transports TEXT NOT NULL,
credential_flags TEXT NOT NULL,
authenticator TEXT NOT NULL,

created_at bigint NOT NULL DEFAULT now_utc_micro_seconds(),

CONSTRAINT fk_passkey_credentials_passkey_id FOREIGN KEY(passkey_id) REFERENCES passkeys(id) ON DELETE CASCADE
);

CREATE TABLE
    IF NOT EXISTS webauthn_sessions(
        id uuid PRIMARY KEY NOT NULL,

challenge TEXT NOT NULL UNIQUE,

user_id BIGINT NOT NULL,
-- this is meant to be []byte but we'll store it normally for us
allowed_credential_ids TEXT NOT NULL,
-- this is [][]byte, but we'll encode it to b64 to store in db
expires_at bigint NOT NULL,
-- this is time.Time but we'll encode it into unix

user_verification_requirement TEXT NOT NULL,
extensions TEXT NOT NULL,
-- this is a map[string]interface{} but we'll just store it as json

created_at bigint NOT NULL DEFAULT now_utc_micro_seconds(),

CONSTRAINT fk_webauthn_sessions_user_id FOREIGN KEY(user_id) REFERENCES users(user_id) ON DELETE CASCADE
);