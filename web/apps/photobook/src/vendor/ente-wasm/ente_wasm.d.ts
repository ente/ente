/* tslint:disable */
/* eslint-disable */

/**
 * Auth error.
 */
export class AuthError {
    private constructor();
    free(): void;
    [Symbol.dispose](): void;
    /**
     * A machine-readable error code.
     */
    readonly code: string;
    /**
     * Human-readable error message.
     */
    readonly message: string;
}

/**
 * Handle to an open contacts context.
 */
export class ContactsCtxHandle {
    private constructor();
    free(): void;
    [Symbol.dispose](): void;
    /**
     * Return the wrapped root key currently held by this context, if resolved.
     */
    current_wrapped_root_contact_key(): any;
    /**
     * Pull a diff page of contacts.
     */
    get_diff(since_time: bigint, limit: number): Promise<any>;
    /**
     * Fetch and decrypt the profile picture bytes for a contact.
     */
    get_profile_picture(contact_id: string): Promise<Uint8Array>;
    /**
     * Add a trusted legacy contact after sealing the current user's recovery key in Rust.
     */
    legacy_add_contact(email: string, current_user_key_attrs: any, recovery_notice_in_days?: number | null): Promise<void>;
    /**
     * Approve a recovery flow as the account owner.
     */
    legacy_approve_recovery(recovery_id: string, user_id: bigint, emergency_contact_id: bigint): Promise<void>;
    /**
     * Complete the legacy password reset flow fully in Rust.
     */
    legacy_change_password(recovery_id: string, current_user_key_attrs: any, new_password: string): Promise<void>;
    /**
     * Fetch legacy/emergency contact info for the current user.
     */
    legacy_get_info(): Promise<any>;
    /**
     * Lookup a user's public key by email for legacy verify/add flows.
     */
    legacy_public_key(email: string): Promise<any>;
    /**
     * Fetch and decrypt the recovery payload for a ready session.
     */
    legacy_recovery_bundle(recovery_id: string, current_user_key_attrs: any): Promise<any>;
    /**
     * Reject a recovery flow as the account owner.
     */
    legacy_reject_recovery(recovery_id: string, user_id: bigint, emergency_contact_id: bigint): Promise<void>;
    /**
     * Start a recovery flow as the trusted contact.
     */
    legacy_start_recovery(user_id: bigint, emergency_contact_id: bigint): Promise<void>;
    /**
     * Stop a recovery flow as the trusted contact.
     */
    legacy_stop_recovery(recovery_id: string, user_id: bigint, emergency_contact_id: bigint): Promise<void>;
    /**
     * Update a legacy contact relationship state.
     */
    legacy_update_contact(user_id: bigint, emergency_contact_id: bigint, state: any): Promise<void>;
    /**
     * Update the notice period for an existing trusted contact.
     */
    legacy_update_recovery_notice(emergency_contact_id: bigint, recovery_notice_in_days: number): Promise<void>;
    /**
     * Generate the mnemonic-style verification ID for a public key.
     */
    legacy_verification_id(public_key_b64: string): string;
    /**
     * Update auth token without rebuilding the contacts context.
     */
    update_auth_token(auth_token: string): void;
}

/**
 * Contacts error.
 */
export class ContactsError {
    private constructor();
    free(): void;
    [Symbol.dispose](): void;
    /**
     * Machine-readable error code.
     */
    readonly code: string;
    /**
     * Human-readable error message.
     */
    readonly message: string;
}

/**
 * Crypto error.
 */
export class CryptoError {
    private constructor();
    free(): void;
    [Symbol.dispose](): void;
    /**
     * A machine-readable error code.
     */
    readonly code: string;
    /**
     * Human-readable error message.
     */
    readonly message: string;
}

/**
 * A X25519 public/secret keypair.
 */
export class CryptoKeyPair {
    private constructor();
    free(): void;
    [Symbol.dispose](): void;
    readonly public_key: string;
    readonly secret_key: string;
}

/**
 * Incremental chunk decryptor for large file downloads.
 */
export class CryptoStreamDecryptor {
    free(): void;
    [Symbol.dispose](): void;
    decrypt_chunk(ciphertext: Uint8Array): Uint8Array;
    constructor(decryption_header_b64: string, key_b64: string);
    readonly decryption_chunk_size: number;
    readonly is_finalized: boolean;
}

/**
 * Incremental chunk encryptor for large file uploads.
 *
 * The browser reads the file in chunks and passes each chunk to this object,
 * which keeps the secretstream state in Rust and returns encrypted bytes for
 * the caller to upload.
 */
export class CryptoStreamEncryptor {
    free(): void;
    [Symbol.dispose](): void;
    encrypt_chunk(plaintext: Uint8Array, is_final: boolean): Uint8Array;
    constructor();
    readonly decryption_header: string;
    readonly key: string;
}

/**
 * Result of decrypting only the master key and secret key.
 */
export class DecryptedKeys {
    private constructor();
    free(): void;
    [Symbol.dispose](): void;
    /**
     * Master key (base64).
     */
    readonly master_key: string;
    /**
     * Secret key (base64).
     */
    readonly secret_key: string;
}

/**
 * Decrypted secrets after successful authentication.
 */
export class DecryptedSecrets {
    private constructor();
    free(): void;
    [Symbol.dispose](): void;
    /**
     * Master key (base64).
     */
    readonly master_key: string;
    /**
     * Secret key (base64).
     */
    readonly secret_key: string;
    /**
     * Auth token (URL-safe base64).
     */
    readonly token: string;
}

/**
 * A SecretStream (blob) encryption result.
 */
export class EncryptedBlob {
    private constructor();
    free(): void;
    [Symbol.dispose](): void;
    readonly decryption_header: string;
    readonly encrypted_data: string;
}

/**
 * A SecretBox encryption result.
 *
 * Wire format is compatible with libsodium's `crypto_secretbox_easy`.
 */
export class EncryptedBox {
    private constructor();
    free(): void;
    [Symbol.dispose](): void;
    readonly encrypted_data: string;
    readonly nonce: string;
}

/**
 * A chunked SecretStream encryption result (for file content).
 *
 * Unlike [`EncryptedBlob`] which encrypts data as a single message, this
 * encrypts data in 4 MB chunks using the streaming API — the same format used
 * for encrypted file content throughout Ente.
 */
export class EncryptedStreamResult {
    private constructor();
    free(): void;
    [Symbol.dispose](): void;
    /**
     * The decryption header as base64.
     */
    readonly decryption_header: string;
    /**
     * The encrypted ciphertext as base64.
     */
    readonly encrypted_data: string;
    /**
     * The file encryption key (32 bytes) as base64.
     *
     * A new random key is generated for each encryption.
     */
    readonly key: string;
    /**
     * MD5 hash of the encrypted data as base64.
     */
    readonly md5_hash: string;
}

/**
 * A generated KEK and its derivation parameters.
 */
export class GeneratedKek {
    private constructor();
    free(): void;
    [Symbol.dispose](): void;
    /**
     * Derived KEK (base64).
     */
    readonly key: string;
    /**
     * Argon2 memory limit in bytes.
     */
    readonly mem_limit: number;
    /**
     * Argon2 operations limit.
     */
    readonly ops_limit: number;
    /**
     * Salt used for derivation (base64).
     */
    readonly salt: string;
}

/**
 * SRP setup payload generated from a KEK.
 */
export class GeneratedSrpSetup {
    private constructor();
    free(): void;
    [Symbol.dispose](): void;
    /**
     * SRP login sub-key (base64, 16 bytes).
     */
    readonly login_sub_key: string;
    /**
     * SRP salt (base64).
     */
    readonly srp_salt: string;
    /**
     * SRP verifier (base64).
     */
    readonly srp_verifier: string;
}

/**
 * HTTP client for making requests to the Ente API.
 */
export class HttpClient {
    free(): void;
    [Symbol.dispose](): void;
    /**
     * GET request, returns response body as text.
     */
    get(path: string): Promise<string>;
    /**
     * Create a client with the given base URL.
     */
    constructor(base_url: string);
}

/**
 * HTTP client error.
 */
export class HttpError {
    private constructor();
    free(): void;
    [Symbol.dispose](): void;
    /**
     * Error code: "invalid_url", "network", "http", or "parse".
     */
    readonly code: string;
    /**
     * Error message.
     */
    readonly message: string;
    /**
     * HTTP status code (only for "http" errors).
     */
    readonly status: number | undefined;
}

/**
 * SRP credentials derived from a password.
 */
export class SrpCredentials {
    private constructor();
    free(): void;
    [Symbol.dispose](): void;
    /**
     * Key-encryption-key (base64).
     */
    readonly kek: string;
    /**
     * SRP login key (base64, 16 bytes).
     */
    readonly login_key: string;
}

/**
 * SRP (Secure Remote Password) session.
 *
 * This is a small state machine:
 * - Create session
 * - Send `public_a()` to server
 * - Receive `srpB` from server, compute `srpM1`
 * - Receive `srpM2` from server, verify
 */
export class SrpSession {
    free(): void;
    [Symbol.dispose](): void;
    /**
     * Compute the client proof M1 from the server's public value B (base64).
     */
    compute_m1(srp_b_b64: string): string;
    /**
     * Create a new SRP session.
     *
     * All inputs are base64 strings except `srp_user_id`.
     */
    constructor(srp_user_id: string, srp_salt_b64: string, login_key_b64: string);
    /**
     * Get the public ephemeral value A as base64.
     */
    public_a(): string;
    /**
     * Verify the server proof M2 (base64).
     */
    verify_m2(srp_m2_b64: string): void;
}

/**
 * Decrypt only the master key and secret key.
 *
 * Useful when the auth token is obtained separately.
 */
export function auth_decrypt_keys_only(kek_b64: string, key_attrs: any): DecryptedKeys;

/**
 * Decrypt the master key, secret key and auth token.
 *
 * `key_attrs` should be the `keyAttributes` object from the auth response.
 * `encrypted_token_b64` is the `encryptedToken` string from the auth response.
 */
export function auth_decrypt_secrets(kek_b64: string, key_attrs: any, encrypted_token_b64: string): DecryptedSecrets;

/**
 * Derive the key-encryption-key (KEK) from password and KEK parameters.
 *
 * Returns the KEK as base64.
 */
export function auth_derive_kek(password: string, kek_salt_b64: string, mem_limit: number, ops_limit: number): string;

/**
 * Derive SRP credentials (KEK + login key) from a password and SRP attributes.
 *
 * `srp_attrs` must match the shape returned by the Ente API's
 * `/users/srp/attributes` endpoint (i.e. camelCased fields).
 */
export function auth_derive_srp_credentials(password: string, srp_attrs: any): SrpCredentials;

/**
 * Generate a KEK using the current interactive web derivation policy.
 */
export function auth_generate_interactive_kek(password: string): GeneratedKek;

/**
 * Generate a KEK using the current sensitive web derivation policy.
 */
export function auth_generate_sensitive_kek(password: string): GeneratedKek;

/**
 * Generate the SRP setup payload for a given KEK and SRP user ID.
 */
export function auth_generate_srp_setup(kek_b64: string, srp_user_id: string): GeneratedSrpSetup;

/**
 * Convert a recovery key mnemonic or legacy hex string into base64 bytes.
 */
export function auth_recovery_key_from_mnemonic_or_hex(input: string): string;

/**
 * Convert a base64-encoded recovery key into its English mnemonic.
 */
export function auth_recovery_key_to_mnemonic(recovery_key_b64: string): string;

/**
 * Open contacts context for web.
 */
export function contacts_open_ctx(input: any): Promise<any>;

/**
 * Seal (anonymous public-key encrypt) `data_b64` for `recipient_public_key_b64`.
 *
 * Wire format matches libsodium `crypto_box_seal`.
 */
export function crypto_box_seal(data_b64: string, recipient_public_key_b64: string): string;

/**
 * Open (decrypt) a sealed box.
 *
 * Returns the plaintext as base64.
 */
export function crypto_box_seal_open(sealed_b64: string, recipient_public_key_b64: string, recipient_secret_key_b64: string): string;

/**
 * Decrypt a SecretStream (blob) ciphertext.
 *
 * Returns the plaintext as base64.
 */
export function crypto_decrypt_blob(encrypted_data_b64: string, decryption_header_b64: string, key_b64: string): string;

/**
 * Legacy decrypt for SecretStream (blob) ciphertext that may not carry
 * a final tag.
 *
 * Prefer using [`crypto_decrypt_blob`]. This function exists as a migration
 * fallback for older data written without the final secretstream tag.
 */
export function crypto_decrypt_blob_legacy(encrypted_data_b64: string, decryption_header_b64: string, key_b64: string): string;

/**
 * Decrypt a SecretBox ciphertext using `key_b64` and `nonce_b64`.
 *
 * Returns the plaintext as base64.
 */
export function crypto_decrypt_box(encrypted_data_b64: string, nonce_b64: string, key_b64: string): string;

/**
 * Decrypt chunked SecretStream data (file content).
 *
 * Unlike `crypto_decrypt_blob` which handles single-message blobs, this
 * function handles multi-chunk streaming data encrypted with 4 MB chunks
 * (the format used for encrypted file content).
 *
 * Returns the plaintext as base64.
 */
export function crypto_decrypt_stream(encrypted_data_b64: string, decryption_header_b64: string, key_b64: string): string;

/**
 * Derive a 32-byte key from `password` using Argon2id.
 *
 * Returns the derived key as base64.
 */
export function crypto_derive_key(password: string, salt_b64: string, mem_limit: number, ops_limit: number): string;

/**
 * Derive the SRP login key from a 32-byte master key.
 *
 * Returns the 16-byte login key as base64.
 */
export function crypto_derive_login_key(master_key_b64: string): string;

/**
 * Derive a subkey using BLAKE2b KDF (libsodium compatible).
 *
 * Returns the derived subkey as base64.
 */
export function crypto_derive_subkey(key_b64: string, subkey_len: number, subkey_id: bigint, context: string): string;

/**
 * Encrypt `data_b64` using SecretStream (single-message blob) with `key_b64`.
 */
export function crypto_encrypt_blob(data_b64: string, key_b64: string): EncryptedBlob;

/**
 * Encrypt `data_b64` using SecretBox with `key_b64`.
 *
 * Returns ciphertext (`encrypted_data`) and nonce as base64.
 */
export function crypto_encrypt_box(data_b64: string, key_b64: string): EncryptedBox;

/**
 * Encrypt file data using chunked SecretStream (4 MB chunks) and compute MD5.
 *
 * Generates a new random stream key, encrypts the data in 4 MB chunks (the
 * same format produced by the mobile and desktop clients), and computes the
 * MD5 hash of the ciphertext.
 *
 * Returns the encrypted data, decryption header, MD5 hash, and generated key
 * — all as base64 strings.
 */
export function crypto_encrypt_stream(data_b64: string): EncryptedStreamResult;

/**
 * Encrypt data using chunked SecretStream with an existing key.
 *
 * Same as [`crypto_encrypt_stream`] but uses the provided key instead of
 * generating a new one. Useful for encrypting thumbnails with the same file key.
 */
export function crypto_encrypt_stream_with_key(data_b64: string, key_b64: string): EncryptedStreamResult;

/**
 * Generate a random 32-byte SecretBox key and return it as base64.
 */
export function crypto_generate_key(): string;

/**
 * Generate a random X25519 keypair and return it as base64.
 */
export function crypto_generate_keypair(): CryptoKeyPair;

/**
 * Generate a random 16-byte salt and return it as base64.
 */
export function crypto_generate_salt(): string;

/**
 * Generate a random 32-byte SecretStream key and return it as base64.
 */
export function crypto_generate_stream_key(): string;

/**
 * Initialize the crypto backend.
 *
 * This is a no-op for the pure-Rust implementation, but is provided for API
 * symmetry with other platforms.
 */
export function crypto_init(): void;

/**
 * Compute the MD5 digest of the provided bytes and return it as base64.
 */
export function crypto_md5_base64(data: Uint8Array): string;

/**
 * Generate the download URL for a file.
 */
export function file_download_url(api_base_url: string, file_id: bigint): string;
