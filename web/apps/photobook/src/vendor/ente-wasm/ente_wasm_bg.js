/**
 * Auth error.
 */
export class AuthError {
    static __wrap(ptr) {
        ptr = ptr >>> 0;
        const obj = Object.create(AuthError.prototype);
        obj.__wbg_ptr = ptr;
        AuthErrorFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        AuthErrorFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_autherror_free(ptr, 0);
    }
    /**
     * A machine-readable error code.
     * @returns {string}
     */
    get code() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.autherror_code(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * Human-readable error message.
     * @returns {string}
     */
    get message() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.autherror_message(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
}
if (Symbol.dispose) AuthError.prototype[Symbol.dispose] = AuthError.prototype.free;

/**
 * Handle to an open contacts context.
 */
export class ContactsCtxHandle {
    static __wrap(ptr) {
        ptr = ptr >>> 0;
        const obj = Object.create(ContactsCtxHandle.prototype);
        obj.__wbg_ptr = ptr;
        ContactsCtxHandleFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        ContactsCtxHandleFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_contactsctxhandle_free(ptr, 0);
    }
    /**
     * Return the wrapped root key currently held by this context, if resolved.
     * @returns {any}
     */
    current_wrapped_root_contact_key() {
        const ret = wasm.contactsctxhandle_current_wrapped_root_contact_key(this.__wbg_ptr);
        if (ret[2]) {
            throw takeFromExternrefTable0(ret[1]);
        }
        return takeFromExternrefTable0(ret[0]);
    }
    /**
     * Pull a diff page of contacts.
     * @param {bigint} since_time
     * @param {number} limit
     * @returns {Promise<any>}
     */
    get_diff(since_time, limit) {
        const ret = wasm.contactsctxhandle_get_diff(this.__wbg_ptr, since_time, limit);
        return ret;
    }
    /**
     * Fetch and decrypt the profile picture bytes for a contact.
     * @param {string} contact_id
     * @returns {Promise<Uint8Array>}
     */
    get_profile_picture(contact_id) {
        const ptr0 = passStringToWasm0(contact_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.contactsctxhandle_get_profile_picture(this.__wbg_ptr, ptr0, len0);
        return ret;
    }
    /**
     * Add a trusted legacy contact after sealing the current user's recovery key in Rust.
     * @param {string} email
     * @param {any} current_user_key_attrs
     * @param {number | null} [recovery_notice_in_days]
     * @returns {Promise<void>}
     */
    legacy_add_contact(email, current_user_key_attrs, recovery_notice_in_days) {
        const ptr0 = passStringToWasm0(email, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.contactsctxhandle_legacy_add_contact(this.__wbg_ptr, ptr0, len0, current_user_key_attrs, isLikeNone(recovery_notice_in_days) ? 0x100000001 : (recovery_notice_in_days) >> 0);
        return ret;
    }
    /**
     * Approve a recovery flow as the account owner.
     * @param {string} recovery_id
     * @param {bigint} user_id
     * @param {bigint} emergency_contact_id
     * @returns {Promise<void>}
     */
    legacy_approve_recovery(recovery_id, user_id, emergency_contact_id) {
        const ptr0 = passStringToWasm0(recovery_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.contactsctxhandle_legacy_approve_recovery(this.__wbg_ptr, ptr0, len0, user_id, emergency_contact_id);
        return ret;
    }
    /**
     * Complete the legacy password reset flow fully in Rust.
     * @param {string} recovery_id
     * @param {any} current_user_key_attrs
     * @param {string} new_password
     * @returns {Promise<void>}
     */
    legacy_change_password(recovery_id, current_user_key_attrs, new_password) {
        const ptr0 = passStringToWasm0(recovery_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ptr1 = passStringToWasm0(new_password, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len1 = WASM_VECTOR_LEN;
        const ret = wasm.contactsctxhandle_legacy_change_password(this.__wbg_ptr, ptr0, len0, current_user_key_attrs, ptr1, len1);
        return ret;
    }
    /**
     * Fetch legacy/emergency contact info for the current user.
     * @returns {Promise<any>}
     */
    legacy_get_info() {
        const ret = wasm.contactsctxhandle_legacy_get_info(this.__wbg_ptr);
        return ret;
    }
    /**
     * Lookup a user's public key by email for legacy verify/add flows.
     * @param {string} email
     * @returns {Promise<any>}
     */
    legacy_public_key(email) {
        const ptr0 = passStringToWasm0(email, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.contactsctxhandle_legacy_public_key(this.__wbg_ptr, ptr0, len0);
        return ret;
    }
    /**
     * Fetch and decrypt the recovery payload for a ready session.
     * @param {string} recovery_id
     * @param {any} current_user_key_attrs
     * @returns {Promise<any>}
     */
    legacy_recovery_bundle(recovery_id, current_user_key_attrs) {
        const ptr0 = passStringToWasm0(recovery_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.contactsctxhandle_legacy_recovery_bundle(this.__wbg_ptr, ptr0, len0, current_user_key_attrs);
        return ret;
    }
    /**
     * Reject a recovery flow as the account owner.
     * @param {string} recovery_id
     * @param {bigint} user_id
     * @param {bigint} emergency_contact_id
     * @returns {Promise<void>}
     */
    legacy_reject_recovery(recovery_id, user_id, emergency_contact_id) {
        const ptr0 = passStringToWasm0(recovery_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.contactsctxhandle_legacy_reject_recovery(this.__wbg_ptr, ptr0, len0, user_id, emergency_contact_id);
        return ret;
    }
    /**
     * Start a recovery flow as the trusted contact.
     * @param {bigint} user_id
     * @param {bigint} emergency_contact_id
     * @returns {Promise<void>}
     */
    legacy_start_recovery(user_id, emergency_contact_id) {
        const ret = wasm.contactsctxhandle_legacy_start_recovery(this.__wbg_ptr, user_id, emergency_contact_id);
        return ret;
    }
    /**
     * Stop a recovery flow as the trusted contact.
     * @param {string} recovery_id
     * @param {bigint} user_id
     * @param {bigint} emergency_contact_id
     * @returns {Promise<void>}
     */
    legacy_stop_recovery(recovery_id, user_id, emergency_contact_id) {
        const ptr0 = passStringToWasm0(recovery_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.contactsctxhandle_legacy_stop_recovery(this.__wbg_ptr, ptr0, len0, user_id, emergency_contact_id);
        return ret;
    }
    /**
     * Update a legacy contact relationship state.
     * @param {bigint} user_id
     * @param {bigint} emergency_contact_id
     * @param {any} state
     * @returns {Promise<void>}
     */
    legacy_update_contact(user_id, emergency_contact_id, state) {
        const ret = wasm.contactsctxhandle_legacy_update_contact(this.__wbg_ptr, user_id, emergency_contact_id, state);
        return ret;
    }
    /**
     * Update the notice period for an existing trusted contact.
     * @param {bigint} emergency_contact_id
     * @param {number} recovery_notice_in_days
     * @returns {Promise<void>}
     */
    legacy_update_recovery_notice(emergency_contact_id, recovery_notice_in_days) {
        const ret = wasm.contactsctxhandle_legacy_update_recovery_notice(this.__wbg_ptr, emergency_contact_id, recovery_notice_in_days);
        return ret;
    }
    /**
     * Generate the mnemonic-style verification ID for a public key.
     * @param {string} public_key_b64
     * @returns {string}
     */
    legacy_verification_id(public_key_b64) {
        let deferred3_0;
        let deferred3_1;
        try {
            const ptr0 = passStringToWasm0(public_key_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
            const len0 = WASM_VECTOR_LEN;
            const ret = wasm.contactsctxhandle_legacy_verification_id(this.__wbg_ptr, ptr0, len0);
            var ptr2 = ret[0];
            var len2 = ret[1];
            if (ret[3]) {
                ptr2 = 0; len2 = 0;
                throw takeFromExternrefTable0(ret[2]);
            }
            deferred3_0 = ptr2;
            deferred3_1 = len2;
            return getStringFromWasm0(ptr2, len2);
        } finally {
            wasm.__wbindgen_free(deferred3_0, deferred3_1, 1);
        }
    }
    /**
     * Update auth token without rebuilding the contacts context.
     * @param {string} auth_token
     */
    update_auth_token(auth_token) {
        const ptr0 = passStringToWasm0(auth_token, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        wasm.contactsctxhandle_update_auth_token(this.__wbg_ptr, ptr0, len0);
    }
}
if (Symbol.dispose) ContactsCtxHandle.prototype[Symbol.dispose] = ContactsCtxHandle.prototype.free;

/**
 * Contacts error.
 */
export class ContactsError {
    static __wrap(ptr) {
        ptr = ptr >>> 0;
        const obj = Object.create(ContactsError.prototype);
        obj.__wbg_ptr = ptr;
        ContactsErrorFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        ContactsErrorFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_contactserror_free(ptr, 0);
    }
    /**
     * Machine-readable error code.
     * @returns {string}
     */
    get code() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.contactserror_code(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * Human-readable error message.
     * @returns {string}
     */
    get message() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.contactserror_message(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
}
if (Symbol.dispose) ContactsError.prototype[Symbol.dispose] = ContactsError.prototype.free;

/**
 * Crypto error.
 */
export class CryptoError {
    static __wrap(ptr) {
        ptr = ptr >>> 0;
        const obj = Object.create(CryptoError.prototype);
        obj.__wbg_ptr = ptr;
        CryptoErrorFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        CryptoErrorFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_cryptoerror_free(ptr, 0);
    }
    /**
     * A machine-readable error code.
     * @returns {string}
     */
    get code() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.cryptoerror_code(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * Human-readable error message.
     * @returns {string}
     */
    get message() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.cryptoerror_message(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
}
if (Symbol.dispose) CryptoError.prototype[Symbol.dispose] = CryptoError.prototype.free;

/**
 * A X25519 public/secret keypair.
 */
export class CryptoKeyPair {
    static __wrap(ptr) {
        ptr = ptr >>> 0;
        const obj = Object.create(CryptoKeyPair.prototype);
        obj.__wbg_ptr = ptr;
        CryptoKeyPairFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        CryptoKeyPairFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_cryptokeypair_free(ptr, 0);
    }
    /**
     * @returns {string}
     */
    get public_key() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.cryptokeypair_public_key(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * @returns {string}
     */
    get secret_key() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.cryptokeypair_secret_key(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
}
if (Symbol.dispose) CryptoKeyPair.prototype[Symbol.dispose] = CryptoKeyPair.prototype.free;

/**
 * Incremental chunk decryptor for large file downloads.
 */
export class CryptoStreamDecryptor {
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        CryptoStreamDecryptorFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_cryptostreamdecryptor_free(ptr, 0);
    }
    /**
     * @param {Uint8Array} ciphertext
     * @returns {Uint8Array}
     */
    decrypt_chunk(ciphertext) {
        const ptr0 = passArray8ToWasm0(ciphertext, wasm.__wbindgen_malloc);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.cryptostreamdecryptor_decrypt_chunk(this.__wbg_ptr, ptr0, len0);
        if (ret[3]) {
            throw takeFromExternrefTable0(ret[2]);
        }
        var v2 = getArrayU8FromWasm0(ret[0], ret[1]).slice();
        wasm.__wbindgen_free(ret[0], ret[1] * 1, 1);
        return v2;
    }
    /**
     * @returns {number}
     */
    get decryption_chunk_size() {
        const ret = wasm.cryptostreamdecryptor_decryption_chunk_size(this.__wbg_ptr);
        return ret >>> 0;
    }
    /**
     * @returns {boolean}
     */
    get is_finalized() {
        const ret = wasm.cryptostreamdecryptor_is_finalized(this.__wbg_ptr);
        return ret !== 0;
    }
    /**
     * @param {string} decryption_header_b64
     * @param {string} key_b64
     */
    constructor(decryption_header_b64, key_b64) {
        const ptr0 = passStringToWasm0(decryption_header_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ptr1 = passStringToWasm0(key_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len1 = WASM_VECTOR_LEN;
        const ret = wasm.cryptostreamdecryptor_new(ptr0, len0, ptr1, len1);
        if (ret[2]) {
            throw takeFromExternrefTable0(ret[1]);
        }
        this.__wbg_ptr = ret[0] >>> 0;
        CryptoStreamDecryptorFinalization.register(this, this.__wbg_ptr, this);
        return this;
    }
}
if (Symbol.dispose) CryptoStreamDecryptor.prototype[Symbol.dispose] = CryptoStreamDecryptor.prototype.free;

/**
 * Incremental chunk encryptor for large file uploads.
 *
 * The browser reads the file in chunks and passes each chunk to this object,
 * which keeps the secretstream state in Rust and returns encrypted bytes for
 * the caller to upload.
 */
export class CryptoStreamEncryptor {
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        CryptoStreamEncryptorFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_cryptostreamencryptor_free(ptr, 0);
    }
    /**
     * @returns {string}
     */
    get decryption_header() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.cryptostreamencryptor_decryption_header(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * @param {Uint8Array} plaintext
     * @param {boolean} is_final
     * @returns {Uint8Array}
     */
    encrypt_chunk(plaintext, is_final) {
        const ptr0 = passArray8ToWasm0(plaintext, wasm.__wbindgen_malloc);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.cryptostreamencryptor_encrypt_chunk(this.__wbg_ptr, ptr0, len0, is_final);
        if (ret[3]) {
            throw takeFromExternrefTable0(ret[2]);
        }
        var v2 = getArrayU8FromWasm0(ret[0], ret[1]).slice();
        wasm.__wbindgen_free(ret[0], ret[1] * 1, 1);
        return v2;
    }
    /**
     * @returns {string}
     */
    get key() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.cryptostreamencryptor_key(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
    constructor() {
        const ret = wasm.cryptostreamencryptor_new();
        if (ret[2]) {
            throw takeFromExternrefTable0(ret[1]);
        }
        this.__wbg_ptr = ret[0] >>> 0;
        CryptoStreamEncryptorFinalization.register(this, this.__wbg_ptr, this);
        return this;
    }
}
if (Symbol.dispose) CryptoStreamEncryptor.prototype[Symbol.dispose] = CryptoStreamEncryptor.prototype.free;

/**
 * Result of decrypting only the master key and secret key.
 */
export class DecryptedKeys {
    static __wrap(ptr) {
        ptr = ptr >>> 0;
        const obj = Object.create(DecryptedKeys.prototype);
        obj.__wbg_ptr = ptr;
        DecryptedKeysFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        DecryptedKeysFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_decryptedkeys_free(ptr, 0);
    }
    /**
     * Master key (base64).
     * @returns {string}
     */
    get master_key() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.decryptedkeys_master_key(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * Secret key (base64).
     * @returns {string}
     */
    get secret_key() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.decryptedkeys_secret_key(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
}
if (Symbol.dispose) DecryptedKeys.prototype[Symbol.dispose] = DecryptedKeys.prototype.free;

/**
 * Decrypted secrets after successful authentication.
 */
export class DecryptedSecrets {
    static __wrap(ptr) {
        ptr = ptr >>> 0;
        const obj = Object.create(DecryptedSecrets.prototype);
        obj.__wbg_ptr = ptr;
        DecryptedSecretsFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        DecryptedSecretsFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_decryptedsecrets_free(ptr, 0);
    }
    /**
     * Master key (base64).
     * @returns {string}
     */
    get master_key() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.decryptedsecrets_master_key(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * Secret key (base64).
     * @returns {string}
     */
    get secret_key() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.decryptedsecrets_secret_key(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * Auth token (URL-safe base64).
     * @returns {string}
     */
    get token() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.decryptedsecrets_token(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
}
if (Symbol.dispose) DecryptedSecrets.prototype[Symbol.dispose] = DecryptedSecrets.prototype.free;

/**
 * A SecretStream (blob) encryption result.
 */
export class EncryptedBlob {
    static __wrap(ptr) {
        ptr = ptr >>> 0;
        const obj = Object.create(EncryptedBlob.prototype);
        obj.__wbg_ptr = ptr;
        EncryptedBlobFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        EncryptedBlobFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_encryptedblob_free(ptr, 0);
    }
    /**
     * @returns {string}
     */
    get decryption_header() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.encryptedblob_decryption_header(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * @returns {string}
     */
    get encrypted_data() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.encryptedblob_encrypted_data(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
}
if (Symbol.dispose) EncryptedBlob.prototype[Symbol.dispose] = EncryptedBlob.prototype.free;

/**
 * A SecretBox encryption result.
 *
 * Wire format is compatible with libsodium's `crypto_secretbox_easy`.
 */
export class EncryptedBox {
    static __wrap(ptr) {
        ptr = ptr >>> 0;
        const obj = Object.create(EncryptedBox.prototype);
        obj.__wbg_ptr = ptr;
        EncryptedBoxFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        EncryptedBoxFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_encryptedbox_free(ptr, 0);
    }
    /**
     * @returns {string}
     */
    get encrypted_data() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.encryptedbox_encrypted_data(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * @returns {string}
     */
    get nonce() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.encryptedbox_nonce(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
}
if (Symbol.dispose) EncryptedBox.prototype[Symbol.dispose] = EncryptedBox.prototype.free;

/**
 * A chunked SecretStream encryption result (for file content).
 *
 * Unlike [`EncryptedBlob`] which encrypts data as a single message, this
 * encrypts data in 4 MB chunks using the streaming API — the same format used
 * for encrypted file content throughout Ente.
 */
export class EncryptedStreamResult {
    static __wrap(ptr) {
        ptr = ptr >>> 0;
        const obj = Object.create(EncryptedStreamResult.prototype);
        obj.__wbg_ptr = ptr;
        EncryptedStreamResultFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        EncryptedStreamResultFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_encryptedstreamresult_free(ptr, 0);
    }
    /**
     * The decryption header as base64.
     * @returns {string}
     */
    get decryption_header() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.encryptedstreamresult_decryption_header(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * The encrypted ciphertext as base64.
     * @returns {string}
     */
    get encrypted_data() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.encryptedstreamresult_encrypted_data(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * The file encryption key (32 bytes) as base64.
     *
     * A new random key is generated for each encryption.
     * @returns {string}
     */
    get key() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.encryptedstreamresult_key(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * MD5 hash of the encrypted data as base64.
     * @returns {string}
     */
    get md5_hash() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.encryptedstreamresult_md5_hash(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
}
if (Symbol.dispose) EncryptedStreamResult.prototype[Symbol.dispose] = EncryptedStreamResult.prototype.free;

/**
 * A generated KEK and its derivation parameters.
 */
export class GeneratedKek {
    static __wrap(ptr) {
        ptr = ptr >>> 0;
        const obj = Object.create(GeneratedKek.prototype);
        obj.__wbg_ptr = ptr;
        GeneratedKekFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        GeneratedKekFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_generatedkek_free(ptr, 0);
    }
    /**
     * Derived KEK (base64).
     * @returns {string}
     */
    get key() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.generatedkek_key(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * Argon2 memory limit in bytes.
     * @returns {number}
     */
    get mem_limit() {
        const ret = wasm.generatedkek_mem_limit(this.__wbg_ptr);
        return ret >>> 0;
    }
    /**
     * Argon2 operations limit.
     * @returns {number}
     */
    get ops_limit() {
        const ret = wasm.generatedkek_ops_limit(this.__wbg_ptr);
        return ret >>> 0;
    }
    /**
     * Salt used for derivation (base64).
     * @returns {string}
     */
    get salt() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.generatedkek_salt(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
}
if (Symbol.dispose) GeneratedKek.prototype[Symbol.dispose] = GeneratedKek.prototype.free;

/**
 * SRP setup payload generated from a KEK.
 */
export class GeneratedSrpSetup {
    static __wrap(ptr) {
        ptr = ptr >>> 0;
        const obj = Object.create(GeneratedSrpSetup.prototype);
        obj.__wbg_ptr = ptr;
        GeneratedSrpSetupFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        GeneratedSrpSetupFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_generatedsrpsetup_free(ptr, 0);
    }
    /**
     * SRP login sub-key (base64, 16 bytes).
     * @returns {string}
     */
    get login_sub_key() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.generatedsrpsetup_login_sub_key(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * SRP salt (base64).
     * @returns {string}
     */
    get srp_salt() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.generatedsrpsetup_srp_salt(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * SRP verifier (base64).
     * @returns {string}
     */
    get srp_verifier() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.generatedsrpsetup_srp_verifier(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
}
if (Symbol.dispose) GeneratedSrpSetup.prototype[Symbol.dispose] = GeneratedSrpSetup.prototype.free;

/**
 * HTTP client for making requests to the Ente API.
 */
export class HttpClient {
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        HttpClientFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_httpclient_free(ptr, 0);
    }
    /**
     * GET request, returns response body as text.
     * @param {string} path
     * @returns {Promise<string>}
     */
    get(path) {
        const ptr0 = passStringToWasm0(path, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.httpclient_get(this.__wbg_ptr, ptr0, len0);
        return ret;
    }
    /**
     * Create a client with the given base URL.
     * @param {string} base_url
     */
    constructor(base_url) {
        const ptr0 = passStringToWasm0(base_url, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.httpclient_new(ptr0, len0);
        this.__wbg_ptr = ret >>> 0;
        HttpClientFinalization.register(this, this.__wbg_ptr, this);
        return this;
    }
}
if (Symbol.dispose) HttpClient.prototype[Symbol.dispose] = HttpClient.prototype.free;

/**
 * HTTP client error.
 */
export class HttpError {
    static __wrap(ptr) {
        ptr = ptr >>> 0;
        const obj = Object.create(HttpError.prototype);
        obj.__wbg_ptr = ptr;
        HttpErrorFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        HttpErrorFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_httperror_free(ptr, 0);
    }
    /**
     * Error code: "invalid_url", "network", "http", or "parse".
     * @returns {string}
     */
    get code() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.httperror_code(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * Error message.
     * @returns {string}
     */
    get message() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.httperror_message(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * HTTP status code (only for "http" errors).
     * @returns {number | undefined}
     */
    get status() {
        const ret = wasm.httperror_status(this.__wbg_ptr);
        return ret === 0xFFFFFF ? undefined : ret;
    }
}
if (Symbol.dispose) HttpError.prototype[Symbol.dispose] = HttpError.prototype.free;

/**
 * SRP credentials derived from a password.
 */
export class SrpCredentials {
    static __wrap(ptr) {
        ptr = ptr >>> 0;
        const obj = Object.create(SrpCredentials.prototype);
        obj.__wbg_ptr = ptr;
        SrpCredentialsFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        SrpCredentialsFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_srpcredentials_free(ptr, 0);
    }
    /**
     * Key-encryption-key (base64).
     * @returns {string}
     */
    get kek() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.srpcredentials_kek(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * SRP login key (base64, 16 bytes).
     * @returns {string}
     */
    get login_key() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.srpcredentials_login_key(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
}
if (Symbol.dispose) SrpCredentials.prototype[Symbol.dispose] = SrpCredentials.prototype.free;

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
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        SrpSessionFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_srpsession_free(ptr, 0);
    }
    /**
     * Compute the client proof M1 from the server's public value B (base64).
     * @param {string} srp_b_b64
     * @returns {string}
     */
    compute_m1(srp_b_b64) {
        let deferred3_0;
        let deferred3_1;
        try {
            const ptr0 = passStringToWasm0(srp_b_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
            const len0 = WASM_VECTOR_LEN;
            const ret = wasm.srpsession_compute_m1(this.__wbg_ptr, ptr0, len0);
            var ptr2 = ret[0];
            var len2 = ret[1];
            if (ret[3]) {
                ptr2 = 0; len2 = 0;
                throw takeFromExternrefTable0(ret[2]);
            }
            deferred3_0 = ptr2;
            deferred3_1 = len2;
            return getStringFromWasm0(ptr2, len2);
        } finally {
            wasm.__wbindgen_free(deferred3_0, deferred3_1, 1);
        }
    }
    /**
     * Create a new SRP session.
     *
     * All inputs are base64 strings except `srp_user_id`.
     * @param {string} srp_user_id
     * @param {string} srp_salt_b64
     * @param {string} login_key_b64
     */
    constructor(srp_user_id, srp_salt_b64, login_key_b64) {
        const ptr0 = passStringToWasm0(srp_user_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ptr1 = passStringToWasm0(srp_salt_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len1 = WASM_VECTOR_LEN;
        const ptr2 = passStringToWasm0(login_key_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len2 = WASM_VECTOR_LEN;
        const ret = wasm.srpsession_new(ptr0, len0, ptr1, len1, ptr2, len2);
        if (ret[2]) {
            throw takeFromExternrefTable0(ret[1]);
        }
        this.__wbg_ptr = ret[0] >>> 0;
        SrpSessionFinalization.register(this, this.__wbg_ptr, this);
        return this;
    }
    /**
     * Get the public ephemeral value A as base64.
     * @returns {string}
     */
    public_a() {
        let deferred1_0;
        let deferred1_1;
        try {
            const ret = wasm.srpsession_public_a(this.__wbg_ptr);
            deferred1_0 = ret[0];
            deferred1_1 = ret[1];
            return getStringFromWasm0(ret[0], ret[1]);
        } finally {
            wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * Verify the server proof M2 (base64).
     * @param {string} srp_m2_b64
     */
    verify_m2(srp_m2_b64) {
        const ptr0 = passStringToWasm0(srp_m2_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.srpsession_verify_m2(this.__wbg_ptr, ptr0, len0);
        if (ret[1]) {
            throw takeFromExternrefTable0(ret[0]);
        }
    }
}
if (Symbol.dispose) SrpSession.prototype[Symbol.dispose] = SrpSession.prototype.free;

/**
 * Decrypt only the master key and secret key.
 *
 * Useful when the auth token is obtained separately.
 * @param {string} kek_b64
 * @param {any} key_attrs
 * @returns {DecryptedKeys}
 */
export function auth_decrypt_keys_only(kek_b64, key_attrs) {
    const ptr0 = passStringToWasm0(kek_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.auth_decrypt_keys_only(ptr0, len0, key_attrs);
    if (ret[2]) {
        throw takeFromExternrefTable0(ret[1]);
    }
    return DecryptedKeys.__wrap(ret[0]);
}

/**
 * Decrypt the master key, secret key and auth token.
 *
 * `key_attrs` should be the `keyAttributes` object from the auth response.
 * `encrypted_token_b64` is the `encryptedToken` string from the auth response.
 * @param {string} kek_b64
 * @param {any} key_attrs
 * @param {string} encrypted_token_b64
 * @returns {DecryptedSecrets}
 */
export function auth_decrypt_secrets(kek_b64, key_attrs, encrypted_token_b64) {
    const ptr0 = passStringToWasm0(kek_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ptr1 = passStringToWasm0(encrypted_token_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len1 = WASM_VECTOR_LEN;
    const ret = wasm.auth_decrypt_secrets(ptr0, len0, key_attrs, ptr1, len1);
    if (ret[2]) {
        throw takeFromExternrefTable0(ret[1]);
    }
    return DecryptedSecrets.__wrap(ret[0]);
}

/**
 * Derive the key-encryption-key (KEK) from password and KEK parameters.
 *
 * Returns the KEK as base64.
 * @param {string} password
 * @param {string} kek_salt_b64
 * @param {number} mem_limit
 * @param {number} ops_limit
 * @returns {string}
 */
export function auth_derive_kek(password, kek_salt_b64, mem_limit, ops_limit) {
    let deferred4_0;
    let deferred4_1;
    try {
        const ptr0 = passStringToWasm0(password, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ptr1 = passStringToWasm0(kek_salt_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len1 = WASM_VECTOR_LEN;
        const ret = wasm.auth_derive_kek(ptr0, len0, ptr1, len1, mem_limit, ops_limit);
        var ptr3 = ret[0];
        var len3 = ret[1];
        if (ret[3]) {
            ptr3 = 0; len3 = 0;
            throw takeFromExternrefTable0(ret[2]);
        }
        deferred4_0 = ptr3;
        deferred4_1 = len3;
        return getStringFromWasm0(ptr3, len3);
    } finally {
        wasm.__wbindgen_free(deferred4_0, deferred4_1, 1);
    }
}

/**
 * Derive SRP credentials (KEK + login key) from a password and SRP attributes.
 *
 * `srp_attrs` must match the shape returned by the Ente API's
 * `/users/srp/attributes` endpoint (i.e. camelCased fields).
 * @param {string} password
 * @param {any} srp_attrs
 * @returns {SrpCredentials}
 */
export function auth_derive_srp_credentials(password, srp_attrs) {
    const ptr0 = passStringToWasm0(password, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.auth_derive_srp_credentials(ptr0, len0, srp_attrs);
    if (ret[2]) {
        throw takeFromExternrefTable0(ret[1]);
    }
    return SrpCredentials.__wrap(ret[0]);
}

/**
 * Generate a KEK using the current interactive web derivation policy.
 * @param {string} password
 * @returns {GeneratedKek}
 */
export function auth_generate_interactive_kek(password) {
    const ptr0 = passStringToWasm0(password, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.auth_generate_interactive_kek(ptr0, len0);
    if (ret[2]) {
        throw takeFromExternrefTable0(ret[1]);
    }
    return GeneratedKek.__wrap(ret[0]);
}

/**
 * Generate a KEK using the current sensitive web derivation policy.
 * @param {string} password
 * @returns {GeneratedKek}
 */
export function auth_generate_sensitive_kek(password) {
    const ptr0 = passStringToWasm0(password, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.auth_generate_sensitive_kek(ptr0, len0);
    if (ret[2]) {
        throw takeFromExternrefTable0(ret[1]);
    }
    return GeneratedKek.__wrap(ret[0]);
}

/**
 * Generate the SRP setup payload for a given KEK and SRP user ID.
 * @param {string} kek_b64
 * @param {string} srp_user_id
 * @returns {GeneratedSrpSetup}
 */
export function auth_generate_srp_setup(kek_b64, srp_user_id) {
    const ptr0 = passStringToWasm0(kek_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ptr1 = passStringToWasm0(srp_user_id, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len1 = WASM_VECTOR_LEN;
    const ret = wasm.auth_generate_srp_setup(ptr0, len0, ptr1, len1);
    if (ret[2]) {
        throw takeFromExternrefTable0(ret[1]);
    }
    return GeneratedSrpSetup.__wrap(ret[0]);
}

/**
 * Convert a recovery key mnemonic or legacy hex string into base64 bytes.
 * @param {string} input
 * @returns {string}
 */
export function auth_recovery_key_from_mnemonic_or_hex(input) {
    let deferred3_0;
    let deferred3_1;
    try {
        const ptr0 = passStringToWasm0(input, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.auth_recovery_key_from_mnemonic_or_hex(ptr0, len0);
        var ptr2 = ret[0];
        var len2 = ret[1];
        if (ret[3]) {
            ptr2 = 0; len2 = 0;
            throw takeFromExternrefTable0(ret[2]);
        }
        deferred3_0 = ptr2;
        deferred3_1 = len2;
        return getStringFromWasm0(ptr2, len2);
    } finally {
        wasm.__wbindgen_free(deferred3_0, deferred3_1, 1);
    }
}

/**
 * Convert a base64-encoded recovery key into its English mnemonic.
 * @param {string} recovery_key_b64
 * @returns {string}
 */
export function auth_recovery_key_to_mnemonic(recovery_key_b64) {
    let deferred3_0;
    let deferred3_1;
    try {
        const ptr0 = passStringToWasm0(recovery_key_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.auth_recovery_key_to_mnemonic(ptr0, len0);
        var ptr2 = ret[0];
        var len2 = ret[1];
        if (ret[3]) {
            ptr2 = 0; len2 = 0;
            throw takeFromExternrefTable0(ret[2]);
        }
        deferred3_0 = ptr2;
        deferred3_1 = len2;
        return getStringFromWasm0(ptr2, len2);
    } finally {
        wasm.__wbindgen_free(deferred3_0, deferred3_1, 1);
    }
}

/**
 * Open contacts context for web.
 * @param {any} input
 * @returns {Promise<any>}
 */
export function contacts_open_ctx(input) {
    const ret = wasm.contacts_open_ctx(input);
    return ret;
}

/**
 * Seal (anonymous public-key encrypt) `data_b64` for `recipient_public_key_b64`.
 *
 * Wire format matches libsodium `crypto_box_seal`.
 * @param {string} data_b64
 * @param {string} recipient_public_key_b64
 * @returns {string}
 */
export function crypto_box_seal(data_b64, recipient_public_key_b64) {
    let deferred4_0;
    let deferred4_1;
    try {
        const ptr0 = passStringToWasm0(data_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ptr1 = passStringToWasm0(recipient_public_key_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len1 = WASM_VECTOR_LEN;
        const ret = wasm.crypto_box_seal(ptr0, len0, ptr1, len1);
        var ptr3 = ret[0];
        var len3 = ret[1];
        if (ret[3]) {
            ptr3 = 0; len3 = 0;
            throw takeFromExternrefTable0(ret[2]);
        }
        deferred4_0 = ptr3;
        deferred4_1 = len3;
        return getStringFromWasm0(ptr3, len3);
    } finally {
        wasm.__wbindgen_free(deferred4_0, deferred4_1, 1);
    }
}

/**
 * Open (decrypt) a sealed box.
 *
 * Returns the plaintext as base64.
 * @param {string} sealed_b64
 * @param {string} recipient_public_key_b64
 * @param {string} recipient_secret_key_b64
 * @returns {string}
 */
export function crypto_box_seal_open(sealed_b64, recipient_public_key_b64, recipient_secret_key_b64) {
    let deferred5_0;
    let deferred5_1;
    try {
        const ptr0 = passStringToWasm0(sealed_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ptr1 = passStringToWasm0(recipient_public_key_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len1 = WASM_VECTOR_LEN;
        const ptr2 = passStringToWasm0(recipient_secret_key_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len2 = WASM_VECTOR_LEN;
        const ret = wasm.crypto_box_seal_open(ptr0, len0, ptr1, len1, ptr2, len2);
        var ptr4 = ret[0];
        var len4 = ret[1];
        if (ret[3]) {
            ptr4 = 0; len4 = 0;
            throw takeFromExternrefTable0(ret[2]);
        }
        deferred5_0 = ptr4;
        deferred5_1 = len4;
        return getStringFromWasm0(ptr4, len4);
    } finally {
        wasm.__wbindgen_free(deferred5_0, deferred5_1, 1);
    }
}

/**
 * Decrypt a SecretStream (blob) ciphertext.
 *
 * Returns the plaintext as base64.
 * @param {string} encrypted_data_b64
 * @param {string} decryption_header_b64
 * @param {string} key_b64
 * @returns {string}
 */
export function crypto_decrypt_blob(encrypted_data_b64, decryption_header_b64, key_b64) {
    let deferred5_0;
    let deferred5_1;
    try {
        const ptr0 = passStringToWasm0(encrypted_data_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ptr1 = passStringToWasm0(decryption_header_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len1 = WASM_VECTOR_LEN;
        const ptr2 = passStringToWasm0(key_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len2 = WASM_VECTOR_LEN;
        const ret = wasm.crypto_decrypt_blob(ptr0, len0, ptr1, len1, ptr2, len2);
        var ptr4 = ret[0];
        var len4 = ret[1];
        if (ret[3]) {
            ptr4 = 0; len4 = 0;
            throw takeFromExternrefTable0(ret[2]);
        }
        deferred5_0 = ptr4;
        deferred5_1 = len4;
        return getStringFromWasm0(ptr4, len4);
    } finally {
        wasm.__wbindgen_free(deferred5_0, deferred5_1, 1);
    }
}

/**
 * Legacy decrypt for SecretStream (blob) ciphertext that may not carry
 * a final tag.
 *
 * Prefer using [`crypto_decrypt_blob`]. This function exists as a migration
 * fallback for older data written without the final secretstream tag.
 * @param {string} encrypted_data_b64
 * @param {string} decryption_header_b64
 * @param {string} key_b64
 * @returns {string}
 */
export function crypto_decrypt_blob_legacy(encrypted_data_b64, decryption_header_b64, key_b64) {
    let deferred5_0;
    let deferred5_1;
    try {
        const ptr0 = passStringToWasm0(encrypted_data_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ptr1 = passStringToWasm0(decryption_header_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len1 = WASM_VECTOR_LEN;
        const ptr2 = passStringToWasm0(key_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len2 = WASM_VECTOR_LEN;
        const ret = wasm.crypto_decrypt_blob_legacy(ptr0, len0, ptr1, len1, ptr2, len2);
        var ptr4 = ret[0];
        var len4 = ret[1];
        if (ret[3]) {
            ptr4 = 0; len4 = 0;
            throw takeFromExternrefTable0(ret[2]);
        }
        deferred5_0 = ptr4;
        deferred5_1 = len4;
        return getStringFromWasm0(ptr4, len4);
    } finally {
        wasm.__wbindgen_free(deferred5_0, deferred5_1, 1);
    }
}

/**
 * Decrypt a SecretBox ciphertext using `key_b64` and `nonce_b64`.
 *
 * Returns the plaintext as base64.
 * @param {string} encrypted_data_b64
 * @param {string} nonce_b64
 * @param {string} key_b64
 * @returns {string}
 */
export function crypto_decrypt_box(encrypted_data_b64, nonce_b64, key_b64) {
    let deferred5_0;
    let deferred5_1;
    try {
        const ptr0 = passStringToWasm0(encrypted_data_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ptr1 = passStringToWasm0(nonce_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len1 = WASM_VECTOR_LEN;
        const ptr2 = passStringToWasm0(key_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len2 = WASM_VECTOR_LEN;
        const ret = wasm.crypto_decrypt_box(ptr0, len0, ptr1, len1, ptr2, len2);
        var ptr4 = ret[0];
        var len4 = ret[1];
        if (ret[3]) {
            ptr4 = 0; len4 = 0;
            throw takeFromExternrefTable0(ret[2]);
        }
        deferred5_0 = ptr4;
        deferred5_1 = len4;
        return getStringFromWasm0(ptr4, len4);
    } finally {
        wasm.__wbindgen_free(deferred5_0, deferred5_1, 1);
    }
}

/**
 * Decrypt chunked SecretStream data (file content).
 *
 * Unlike `crypto_decrypt_blob` which handles single-message blobs, this
 * function handles multi-chunk streaming data encrypted with 4 MB chunks
 * (the format used for encrypted file content).
 *
 * Returns the plaintext as base64.
 * @param {string} encrypted_data_b64
 * @param {string} decryption_header_b64
 * @param {string} key_b64
 * @returns {string}
 */
export function crypto_decrypt_stream(encrypted_data_b64, decryption_header_b64, key_b64) {
    let deferred5_0;
    let deferred5_1;
    try {
        const ptr0 = passStringToWasm0(encrypted_data_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ptr1 = passStringToWasm0(decryption_header_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len1 = WASM_VECTOR_LEN;
        const ptr2 = passStringToWasm0(key_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len2 = WASM_VECTOR_LEN;
        const ret = wasm.crypto_decrypt_stream(ptr0, len0, ptr1, len1, ptr2, len2);
        var ptr4 = ret[0];
        var len4 = ret[1];
        if (ret[3]) {
            ptr4 = 0; len4 = 0;
            throw takeFromExternrefTable0(ret[2]);
        }
        deferred5_0 = ptr4;
        deferred5_1 = len4;
        return getStringFromWasm0(ptr4, len4);
    } finally {
        wasm.__wbindgen_free(deferred5_0, deferred5_1, 1);
    }
}

/**
 * Derive a 32-byte key from `password` using Argon2id.
 *
 * Returns the derived key as base64.
 * @param {string} password
 * @param {string} salt_b64
 * @param {number} mem_limit
 * @param {number} ops_limit
 * @returns {string}
 */
export function crypto_derive_key(password, salt_b64, mem_limit, ops_limit) {
    let deferred4_0;
    let deferred4_1;
    try {
        const ptr0 = passStringToWasm0(password, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ptr1 = passStringToWasm0(salt_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len1 = WASM_VECTOR_LEN;
        const ret = wasm.crypto_derive_key(ptr0, len0, ptr1, len1, mem_limit, ops_limit);
        var ptr3 = ret[0];
        var len3 = ret[1];
        if (ret[3]) {
            ptr3 = 0; len3 = 0;
            throw takeFromExternrefTable0(ret[2]);
        }
        deferred4_0 = ptr3;
        deferred4_1 = len3;
        return getStringFromWasm0(ptr3, len3);
    } finally {
        wasm.__wbindgen_free(deferred4_0, deferred4_1, 1);
    }
}

/**
 * Derive the SRP login key from a 32-byte master key.
 *
 * Returns the 16-byte login key as base64.
 * @param {string} master_key_b64
 * @returns {string}
 */
export function crypto_derive_login_key(master_key_b64) {
    let deferred3_0;
    let deferred3_1;
    try {
        const ptr0 = passStringToWasm0(master_key_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.crypto_derive_login_key(ptr0, len0);
        var ptr2 = ret[0];
        var len2 = ret[1];
        if (ret[3]) {
            ptr2 = 0; len2 = 0;
            throw takeFromExternrefTable0(ret[2]);
        }
        deferred3_0 = ptr2;
        deferred3_1 = len2;
        return getStringFromWasm0(ptr2, len2);
    } finally {
        wasm.__wbindgen_free(deferred3_0, deferred3_1, 1);
    }
}

/**
 * Derive a subkey using BLAKE2b KDF (libsodium compatible).
 *
 * Returns the derived subkey as base64.
 * @param {string} key_b64
 * @param {number} subkey_len
 * @param {bigint} subkey_id
 * @param {string} context
 * @returns {string}
 */
export function crypto_derive_subkey(key_b64, subkey_len, subkey_id, context) {
    let deferred4_0;
    let deferred4_1;
    try {
        const ptr0 = passStringToWasm0(key_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ptr1 = passStringToWasm0(context, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len1 = WASM_VECTOR_LEN;
        const ret = wasm.crypto_derive_subkey(ptr0, len0, subkey_len, subkey_id, ptr1, len1);
        var ptr3 = ret[0];
        var len3 = ret[1];
        if (ret[3]) {
            ptr3 = 0; len3 = 0;
            throw takeFromExternrefTable0(ret[2]);
        }
        deferred4_0 = ptr3;
        deferred4_1 = len3;
        return getStringFromWasm0(ptr3, len3);
    } finally {
        wasm.__wbindgen_free(deferred4_0, deferred4_1, 1);
    }
}

/**
 * Encrypt `data_b64` using SecretStream (single-message blob) with `key_b64`.
 * @param {string} data_b64
 * @param {string} key_b64
 * @returns {EncryptedBlob}
 */
export function crypto_encrypt_blob(data_b64, key_b64) {
    const ptr0 = passStringToWasm0(data_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ptr1 = passStringToWasm0(key_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len1 = WASM_VECTOR_LEN;
    const ret = wasm.crypto_encrypt_blob(ptr0, len0, ptr1, len1);
    if (ret[2]) {
        throw takeFromExternrefTable0(ret[1]);
    }
    return EncryptedBlob.__wrap(ret[0]);
}

/**
 * Encrypt `data_b64` using SecretBox with `key_b64`.
 *
 * Returns ciphertext (`encrypted_data`) and nonce as base64.
 * @param {string} data_b64
 * @param {string} key_b64
 * @returns {EncryptedBox}
 */
export function crypto_encrypt_box(data_b64, key_b64) {
    const ptr0 = passStringToWasm0(data_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ptr1 = passStringToWasm0(key_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len1 = WASM_VECTOR_LEN;
    const ret = wasm.crypto_encrypt_box(ptr0, len0, ptr1, len1);
    if (ret[2]) {
        throw takeFromExternrefTable0(ret[1]);
    }
    return EncryptedBox.__wrap(ret[0]);
}

/**
 * Encrypt file data using chunked SecretStream (4 MB chunks) and compute MD5.
 *
 * Generates a new random stream key, encrypts the data in 4 MB chunks (the
 * same format produced by the mobile and desktop clients), and computes the
 * MD5 hash of the ciphertext.
 *
 * Returns the encrypted data, decryption header, MD5 hash, and generated key
 * — all as base64 strings.
 * @param {string} data_b64
 * @returns {EncryptedStreamResult}
 */
export function crypto_encrypt_stream(data_b64) {
    const ptr0 = passStringToWasm0(data_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.crypto_encrypt_stream(ptr0, len0);
    if (ret[2]) {
        throw takeFromExternrefTable0(ret[1]);
    }
    return EncryptedStreamResult.__wrap(ret[0]);
}

/**
 * Encrypt data using chunked SecretStream with an existing key.
 *
 * Same as [`crypto_encrypt_stream`] but uses the provided key instead of
 * generating a new one. Useful for encrypting thumbnails with the same file key.
 * @param {string} data_b64
 * @param {string} key_b64
 * @returns {EncryptedStreamResult}
 */
export function crypto_encrypt_stream_with_key(data_b64, key_b64) {
    const ptr0 = passStringToWasm0(data_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ptr1 = passStringToWasm0(key_b64, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len1 = WASM_VECTOR_LEN;
    const ret = wasm.crypto_encrypt_stream_with_key(ptr0, len0, ptr1, len1);
    if (ret[2]) {
        throw takeFromExternrefTable0(ret[1]);
    }
    return EncryptedStreamResult.__wrap(ret[0]);
}

/**
 * Generate a random 32-byte SecretBox key and return it as base64.
 * @returns {string}
 */
export function crypto_generate_key() {
    let deferred1_0;
    let deferred1_1;
    try {
        const ret = wasm.crypto_generate_key();
        deferred1_0 = ret[0];
        deferred1_1 = ret[1];
        return getStringFromWasm0(ret[0], ret[1]);
    } finally {
        wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
}

/**
 * Generate a random X25519 keypair and return it as base64.
 * @returns {CryptoKeyPair}
 */
export function crypto_generate_keypair() {
    const ret = wasm.crypto_generate_keypair();
    if (ret[2]) {
        throw takeFromExternrefTable0(ret[1]);
    }
    return CryptoKeyPair.__wrap(ret[0]);
}

/**
 * Generate a random 16-byte salt and return it as base64.
 * @returns {string}
 */
export function crypto_generate_salt() {
    let deferred1_0;
    let deferred1_1;
    try {
        const ret = wasm.crypto_generate_salt();
        deferred1_0 = ret[0];
        deferred1_1 = ret[1];
        return getStringFromWasm0(ret[0], ret[1]);
    } finally {
        wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
}

/**
 * Generate a random 32-byte SecretStream key and return it as base64.
 * @returns {string}
 */
export function crypto_generate_stream_key() {
    let deferred1_0;
    let deferred1_1;
    try {
        const ret = wasm.crypto_generate_stream_key();
        deferred1_0 = ret[0];
        deferred1_1 = ret[1];
        return getStringFromWasm0(ret[0], ret[1]);
    } finally {
        wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
}

/**
 * Initialize the crypto backend.
 *
 * This is a no-op for the pure-Rust implementation, but is provided for API
 * symmetry with other platforms.
 */
export function crypto_init() {
    const ret = wasm.crypto_init();
    if (ret[1]) {
        throw takeFromExternrefTable0(ret[0]);
    }
}

/**
 * Compute the MD5 digest of the provided bytes and return it as base64.
 * @param {Uint8Array} data
 * @returns {string}
 */
export function crypto_md5_base64(data) {
    let deferred2_0;
    let deferred2_1;
    try {
        const ptr0 = passArray8ToWasm0(data, wasm.__wbindgen_malloc);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.crypto_md5_base64(ptr0, len0);
        deferred2_0 = ret[0];
        deferred2_1 = ret[1];
        return getStringFromWasm0(ret[0], ret[1]);
    } finally {
        wasm.__wbindgen_free(deferred2_0, deferred2_1, 1);
    }
}

/**
 * Generate the download URL for a file.
 * @param {string} api_base_url
 * @param {bigint} file_id
 * @returns {string}
 */
export function file_download_url(api_base_url, file_id) {
    let deferred2_0;
    let deferred2_1;
    try {
        const ptr0 = passStringToWasm0(api_base_url, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.file_download_url(ptr0, len0, file_id);
        deferred2_0 = ret[0];
        deferred2_1 = ret[1];
        return getStringFromWasm0(ret[0], ret[1]);
    } finally {
        wasm.__wbindgen_free(deferred2_0, deferred2_1, 1);
    }
}
export function __wbg_Error_8c4e43fe74559d73(arg0, arg1) {
    const ret = Error(getStringFromWasm0(arg0, arg1));
    return ret;
}
export function __wbg_Number_04624de7d0e8332d(arg0) {
    const ret = Number(arg0);
    return ret;
}
export function __wbg_String_8f0eb39a4a4c2f66(arg0, arg1) {
    const ret = String(arg1);
    const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len1 = WASM_VECTOR_LEN;
    getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
    getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
}
export function __wbg___wbindgen_bigint_get_as_i64_8fcf4ce7f1ca72a2(arg0, arg1) {
    const v = arg1;
    const ret = typeof(v) === 'bigint' ? v : undefined;
    getDataViewMemory0().setBigInt64(arg0 + 8 * 1, isLikeNone(ret) ? BigInt(0) : ret, true);
    getDataViewMemory0().setInt32(arg0 + 4 * 0, !isLikeNone(ret), true);
}
export function __wbg___wbindgen_boolean_get_bbbb1c18aa2f5e25(arg0) {
    const v = arg0;
    const ret = typeof(v) === 'boolean' ? v : undefined;
    return isLikeNone(ret) ? 0xFFFFFF : ret ? 1 : 0;
}
export function __wbg___wbindgen_debug_string_0bc8482c6e3508ae(arg0, arg1) {
    const ret = debugString(arg1);
    const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len1 = WASM_VECTOR_LEN;
    getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
    getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
}
export function __wbg___wbindgen_in_47fa6863be6f2f25(arg0, arg1) {
    const ret = arg0 in arg1;
    return ret;
}
export function __wbg___wbindgen_is_bigint_31b12575b56f32fc(arg0) {
    const ret = typeof(arg0) === 'bigint';
    return ret;
}
export function __wbg___wbindgen_is_function_0095a73b8b156f76(arg0) {
    const ret = typeof(arg0) === 'function';
    return ret;
}
export function __wbg___wbindgen_is_object_5ae8e5880f2c1fbd(arg0) {
    const val = arg0;
    const ret = typeof(val) === 'object' && val !== null;
    return ret;
}
export function __wbg___wbindgen_is_string_cd444516edc5b180(arg0) {
    const ret = typeof(arg0) === 'string';
    return ret;
}
export function __wbg___wbindgen_is_undefined_9e4d92534c42d778(arg0) {
    const ret = arg0 === undefined;
    return ret;
}
export function __wbg___wbindgen_jsval_eq_11888390b0186270(arg0, arg1) {
    const ret = arg0 === arg1;
    return ret;
}
export function __wbg___wbindgen_jsval_loose_eq_9dd77d8cd6671811(arg0, arg1) {
    const ret = arg0 == arg1;
    return ret;
}
export function __wbg___wbindgen_number_get_8ff4255516ccad3e(arg0, arg1) {
    const obj = arg1;
    const ret = typeof(obj) === 'number' ? obj : undefined;
    getDataViewMemory0().setFloat64(arg0 + 8 * 1, isLikeNone(ret) ? 0 : ret, true);
    getDataViewMemory0().setInt32(arg0 + 4 * 0, !isLikeNone(ret), true);
}
export function __wbg___wbindgen_string_get_72fb696202c56729(arg0, arg1) {
    const obj = arg1;
    const ret = typeof(obj) === 'string' ? obj : undefined;
    var ptr1 = isLikeNone(ret) ? 0 : passStringToWasm0(ret, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    var len1 = WASM_VECTOR_LEN;
    getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
    getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
}
export function __wbg___wbindgen_throw_be289d5034ed271b(arg0, arg1) {
    throw new Error(getStringFromWasm0(arg0, arg1));
}
export function __wbg__wbg_cb_unref_d9b87ff7982e3b21(arg0) {
    arg0._wbg_cb_unref();
}
export function __wbg_abort_2f0584e03e8e3950(arg0) {
    arg0.abort();
}
export function __wbg_abort_d549b92d3c665de1(arg0, arg1) {
    arg0.abort(arg1);
}
export function __wbg_append_a992ccc37aa62dc4() { return handleError(function (arg0, arg1, arg2, arg3, arg4) {
    arg0.append(getStringFromWasm0(arg1, arg2), getStringFromWasm0(arg3, arg4));
}, arguments); }
export function __wbg_arrayBuffer_bb54076166006c39() { return handleError(function (arg0) {
    const ret = arg0.arrayBuffer();
    return ret;
}, arguments); }
export function __wbg_autherror_new(arg0) {
    const ret = AuthError.__wrap(arg0);
    return ret;
}
export function __wbg_call_389efe28435a9388() { return handleError(function (arg0, arg1) {
    const ret = arg0.call(arg1);
    return ret;
}, arguments); }
export function __wbg_call_4708e0c13bdc8e95() { return handleError(function (arg0, arg1, arg2) {
    const ret = arg0.call(arg1, arg2);
    return ret;
}, arguments); }
export function __wbg_clearTimeout_42d9ccd50822fd3a(arg0) {
    const ret = clearTimeout(arg0);
    return ret;
}
export function __wbg_contactsctxhandle_new(arg0) {
    const ret = ContactsCtxHandle.__wrap(arg0);
    return ret;
}
export function __wbg_contactserror_new(arg0) {
    const ret = ContactsError.__wrap(arg0);
    return ret;
}
export function __wbg_crypto_86f2631e91b51511(arg0) {
    const ret = arg0.crypto;
    return ret;
}
export function __wbg_cryptoerror_new(arg0) {
    const ret = CryptoError.__wrap(arg0);
    return ret;
}
export function __wbg_done_57b39ecd9addfe81(arg0) {
    const ret = arg0.done;
    return ret;
}
export function __wbg_entries_58c7934c745daac7(arg0) {
    const ret = Object.entries(arg0);
    return ret;
}
export function __wbg_fetch_6bbc32f991730587(arg0) {
    const ret = fetch(arg0);
    return ret;
}
export function __wbg_fetch_afb6a4b6cacf876d(arg0, arg1) {
    const ret = arg0.fetch(arg1);
    return ret;
}
export function __wbg_getRandomValues_b3f15fcbfabb0f8b() { return handleError(function (arg0, arg1) {
    arg0.getRandomValues(arg1);
}, arguments); }
export function __wbg_getRandomValues_d50a9564033a7f85() { return handleError(function (arg0, arg1) {
    globalThis.crypto.getRandomValues(getArrayU8FromWasm0(arg0, arg1));
}, arguments); }
export function __wbg_get_9b94d73e6221f75c(arg0, arg1) {
    const ret = arg0[arg1 >>> 0];
    return ret;
}
export function __wbg_get_b3ed3ad4be2bc8ac() { return handleError(function (arg0, arg1) {
    const ret = Reflect.get(arg0, arg1);
    return ret;
}, arguments); }
export function __wbg_get_with_ref_key_1dc361bd10053bfe(arg0, arg1) {
    const ret = arg0[arg1];
    return ret;
}
export function __wbg_has_d4e53238966c12b6() { return handleError(function (arg0, arg1) {
    const ret = Reflect.has(arg0, arg1);
    return ret;
}, arguments); }
export function __wbg_headers_59a2938db9f80985(arg0) {
    const ret = arg0.headers;
    return ret;
}
export function __wbg_httperror_new(arg0) {
    const ret = HttpError.__wrap(arg0);
    return ret;
}
export function __wbg_instanceof_ArrayBuffer_c367199e2fa2aa04(arg0) {
    let result;
    try {
        result = arg0 instanceof ArrayBuffer;
    } catch (_) {
        result = false;
    }
    const ret = result;
    return ret;
}
export function __wbg_instanceof_Response_ee1d54d79ae41977(arg0) {
    let result;
    try {
        result = arg0 instanceof Response;
    } catch (_) {
        result = false;
    }
    const ret = result;
    return ret;
}
export function __wbg_instanceof_Uint8Array_9b9075935c74707c(arg0) {
    let result;
    try {
        result = arg0 instanceof Uint8Array;
    } catch (_) {
        result = false;
    }
    const ret = result;
    return ret;
}
export function __wbg_isSafeInteger_bfbc7332a9768d2a(arg0) {
    const ret = Number.isSafeInteger(arg0);
    return ret;
}
export function __wbg_iterator_6ff6560ca1568e55() {
    const ret = Symbol.iterator;
    return ret;
}
export function __wbg_length_32ed9a279acd054c(arg0) {
    const ret = arg0.length;
    return ret;
}
export function __wbg_length_35a7bace40f36eac(arg0) {
    const ret = arg0.length;
    return ret;
}
export function __wbg_msCrypto_d562bbe83e0d4b91(arg0) {
    const ret = arg0.msCrypto;
    return ret;
}
export function __wbg_new_361308b2356cecd0() {
    const ret = new Object();
    return ret;
}
export function __wbg_new_3eb36ae241fe6f44() {
    const ret = new Array();
    return ret;
}
export function __wbg_new_64284bd487f9d239() { return handleError(function () {
    const ret = new Headers();
    return ret;
}, arguments); }
export function __wbg_new_b5d9e2fb389fef91(arg0, arg1) {
    try {
        var state0 = {a: arg0, b: arg1};
        var cb0 = (arg0, arg1) => {
            const a = state0.a;
            state0.a = 0;
            try {
                return wasm_bindgen__convert__closures_____invoke__hbd6210b51a56ce9e(a, state0.b, arg0, arg1);
            } finally {
                state0.a = a;
            }
        };
        const ret = new Promise(cb0);
        return ret;
    } finally {
        state0.a = state0.b = 0;
    }
}
export function __wbg_new_b949e7f56150a5d1() { return handleError(function () {
    const ret = new AbortController();
    return ret;
}, arguments); }
export function __wbg_new_dd2b680c8bf6ae29(arg0) {
    const ret = new Uint8Array(arg0);
    return ret;
}
export function __wbg_new_from_slice_a3d2629dc1826784(arg0, arg1) {
    const ret = new Uint8Array(getArrayU8FromWasm0(arg0, arg1));
    return ret;
}
export function __wbg_new_no_args_1c7c842f08d00ebb(arg0, arg1) {
    const ret = new Function(getStringFromWasm0(arg0, arg1));
    return ret;
}
export function __wbg_new_with_length_a2c39cbe88fd8ff1(arg0) {
    const ret = new Uint8Array(arg0 >>> 0);
    return ret;
}
export function __wbg_new_with_str_and_init_a61cbc6bdef21614() { return handleError(function (arg0, arg1, arg2) {
    const ret = new Request(getStringFromWasm0(arg0, arg1), arg2);
    return ret;
}, arguments); }
export function __wbg_next_3482f54c49e8af19() { return handleError(function (arg0) {
    const ret = arg0.next();
    return ret;
}, arguments); }
export function __wbg_next_418f80d8f5303233(arg0) {
    const ret = arg0.next;
    return ret;
}
export function __wbg_node_e1f24f89a7336c2e(arg0) {
    const ret = arg0.node;
    return ret;
}
export function __wbg_process_3975fd6c72f520aa(arg0) {
    const ret = arg0.process;
    return ret;
}
export function __wbg_prototypesetcall_bdcdcc5842e4d77d(arg0, arg1, arg2) {
    Uint8Array.prototype.set.call(getArrayU8FromWasm0(arg0, arg1), arg2);
}
export function __wbg_queueMicrotask_0aa0a927f78f5d98(arg0) {
    const ret = arg0.queueMicrotask;
    return ret;
}
export function __wbg_queueMicrotask_5bb536982f78a56f(arg0) {
    queueMicrotask(arg0);
}
export function __wbg_randomFillSync_f8c153b79f285817() { return handleError(function (arg0, arg1) {
    arg0.randomFillSync(arg1);
}, arguments); }
export function __wbg_require_b74f47fc2d022fd6() { return handleError(function () {
    const ret = module.require;
    return ret;
}, arguments); }
export function __wbg_resolve_002c4b7d9d8f6b64(arg0) {
    const ret = Promise.resolve(arg0);
    return ret;
}
export function __wbg_setTimeout_4ec014681668a581(arg0, arg1) {
    const ret = setTimeout(arg0, arg1);
    return ret;
}
export function __wbg_set_3f1d0b984ed272ed(arg0, arg1, arg2) {
    arg0[arg1] = arg2;
}
export function __wbg_set_6cb8631f80447a67() { return handleError(function (arg0, arg1, arg2) {
    const ret = Reflect.set(arg0, arg1, arg2);
    return ret;
}, arguments); }
export function __wbg_set_body_9a7e00afe3cfe244(arg0, arg1) {
    arg0.body = arg1;
}
export function __wbg_set_cache_315a3ed773a41543(arg0, arg1) {
    arg0.cache = __wbindgen_enum_RequestCache[arg1];
}
export function __wbg_set_credentials_c4a58d2e05ef24fb(arg0, arg1) {
    arg0.credentials = __wbindgen_enum_RequestCredentials[arg1];
}
export function __wbg_set_f43e577aea94465b(arg0, arg1, arg2) {
    arg0[arg1 >>> 0] = arg2;
}
export function __wbg_set_headers_cfc5f4b2c1f20549(arg0, arg1) {
    arg0.headers = arg1;
}
export function __wbg_set_method_c3e20375f5ae7fac(arg0, arg1, arg2) {
    arg0.method = getStringFromWasm0(arg1, arg2);
}
export function __wbg_set_mode_b13642c312648202(arg0, arg1) {
    arg0.mode = __wbindgen_enum_RequestMode[arg1];
}
export function __wbg_set_signal_f2d3f8599248896d(arg0, arg1) {
    arg0.signal = arg1;
}
export function __wbg_signal_d1285ecab4ebc5ad(arg0) {
    const ret = arg0.signal;
    return ret;
}
export function __wbg_static_accessor_GLOBAL_12837167ad935116() {
    const ret = typeof global === 'undefined' ? null : global;
    return isLikeNone(ret) ? 0 : addToExternrefTable0(ret);
}
export function __wbg_static_accessor_GLOBAL_THIS_e628e89ab3b1c95f() {
    const ret = typeof globalThis === 'undefined' ? null : globalThis;
    return isLikeNone(ret) ? 0 : addToExternrefTable0(ret);
}
export function __wbg_static_accessor_SELF_a621d3dfbb60d0ce() {
    const ret = typeof self === 'undefined' ? null : self;
    return isLikeNone(ret) ? 0 : addToExternrefTable0(ret);
}
export function __wbg_static_accessor_WINDOW_f8727f0cf888e0bd() {
    const ret = typeof window === 'undefined' ? null : window;
    return isLikeNone(ret) ? 0 : addToExternrefTable0(ret);
}
export function __wbg_status_89d7e803db911ee7(arg0) {
    const ret = arg0.status;
    return ret;
}
export function __wbg_stringify_8d1cc6ff383e8bae() { return handleError(function (arg0) {
    const ret = JSON.stringify(arg0);
    return ret;
}, arguments); }
export function __wbg_subarray_a96e1fef17ed23cb(arg0, arg1, arg2) {
    const ret = arg0.subarray(arg1 >>> 0, arg2 >>> 0);
    return ret;
}
export function __wbg_text_083b8727c990c8c0() { return handleError(function (arg0) {
    const ret = arg0.text();
    return ret;
}, arguments); }
export function __wbg_then_0d9fe2c7b1857d32(arg0, arg1, arg2) {
    const ret = arg0.then(arg1, arg2);
    return ret;
}
export function __wbg_then_b9e7b3b5f1a9e1b5(arg0, arg1) {
    const ret = arg0.then(arg1);
    return ret;
}
export function __wbg_url_c484c26b1fbf5126(arg0, arg1) {
    const ret = arg1.url;
    const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len1 = WASM_VECTOR_LEN;
    getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
    getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
}
export function __wbg_value_0546255b415e96c1(arg0) {
    const ret = arg0.value;
    return ret;
}
export function __wbg_versions_4e31226f5e8dc909(arg0) {
    const ret = arg0.versions;
    return ret;
}
export function __wbindgen_cast_0000000000000001(arg0, arg1) {
    // Cast intrinsic for `Closure(Closure { dtor_idx: 238, function: Function { arguments: [], shim_idx: 239, ret: Unit, inner_ret: Some(Unit) }, mutable: true }) -> Externref`.
    const ret = makeMutClosure(arg0, arg1, wasm.wasm_bindgen__closure__destroy__h275c4efae8d270a9, wasm_bindgen__convert__closures_____invoke__h243d2fcf3ee145cc);
    return ret;
}
export function __wbindgen_cast_0000000000000002(arg0, arg1) {
    // Cast intrinsic for `Closure(Closure { dtor_idx: 263, function: Function { arguments: [Externref], shim_idx: 264, ret: Unit, inner_ret: Some(Unit) }, mutable: true }) -> Externref`.
    const ret = makeMutClosure(arg0, arg1, wasm.wasm_bindgen__closure__destroy__h830d094018f30114, wasm_bindgen__convert__closures_____invoke__h17f0ca6e490bb5c5);
    return ret;
}
export function __wbindgen_cast_0000000000000003(arg0) {
    // Cast intrinsic for `F64 -> Externref`.
    const ret = arg0;
    return ret;
}
export function __wbindgen_cast_0000000000000004(arg0) {
    // Cast intrinsic for `I64 -> Externref`.
    const ret = arg0;
    return ret;
}
export function __wbindgen_cast_0000000000000005(arg0, arg1) {
    // Cast intrinsic for `Ref(Slice(U8)) -> NamedExternref("Uint8Array")`.
    const ret = getArrayU8FromWasm0(arg0, arg1);
    return ret;
}
export function __wbindgen_cast_0000000000000006(arg0, arg1) {
    // Cast intrinsic for `Ref(String) -> Externref`.
    const ret = getStringFromWasm0(arg0, arg1);
    return ret;
}
export function __wbindgen_cast_0000000000000007(arg0, arg1) {
    var v0 = getArrayU8FromWasm0(arg0, arg1).slice();
    wasm.__wbindgen_free(arg0, arg1 * 1, 1);
    // Cast intrinsic for `Vector(U8) -> Externref`.
    const ret = v0;
    return ret;
}
export function __wbindgen_init_externref_table() {
    const table = wasm.__wbindgen_externrefs;
    const offset = table.grow(4);
    table.set(0, undefined);
    table.set(offset + 0, undefined);
    table.set(offset + 1, null);
    table.set(offset + 2, true);
    table.set(offset + 3, false);
}
function wasm_bindgen__convert__closures_____invoke__h243d2fcf3ee145cc(arg0, arg1) {
    wasm.wasm_bindgen__convert__closures_____invoke__h243d2fcf3ee145cc(arg0, arg1);
}

function wasm_bindgen__convert__closures_____invoke__h17f0ca6e490bb5c5(arg0, arg1, arg2) {
    wasm.wasm_bindgen__convert__closures_____invoke__h17f0ca6e490bb5c5(arg0, arg1, arg2);
}

function wasm_bindgen__convert__closures_____invoke__hbd6210b51a56ce9e(arg0, arg1, arg2, arg3) {
    wasm.wasm_bindgen__convert__closures_____invoke__hbd6210b51a56ce9e(arg0, arg1, arg2, arg3);
}


const __wbindgen_enum_RequestCache = ["default", "no-store", "reload", "no-cache", "force-cache", "only-if-cached"];


const __wbindgen_enum_RequestCredentials = ["omit", "same-origin", "include"];


const __wbindgen_enum_RequestMode = ["same-origin", "no-cors", "cors", "navigate"];
const AuthErrorFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_autherror_free(ptr >>> 0, 1));
const ContactsCtxHandleFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_contactsctxhandle_free(ptr >>> 0, 1));
const ContactsErrorFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_contactserror_free(ptr >>> 0, 1));
const CryptoErrorFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_cryptoerror_free(ptr >>> 0, 1));
const CryptoKeyPairFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_cryptokeypair_free(ptr >>> 0, 1));
const CryptoStreamDecryptorFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_cryptostreamdecryptor_free(ptr >>> 0, 1));
const CryptoStreamEncryptorFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_cryptostreamencryptor_free(ptr >>> 0, 1));
const DecryptedKeysFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_decryptedkeys_free(ptr >>> 0, 1));
const DecryptedSecretsFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_decryptedsecrets_free(ptr >>> 0, 1));
const EncryptedBlobFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_encryptedblob_free(ptr >>> 0, 1));
const EncryptedBoxFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_encryptedbox_free(ptr >>> 0, 1));
const EncryptedStreamResultFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_encryptedstreamresult_free(ptr >>> 0, 1));
const GeneratedKekFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_generatedkek_free(ptr >>> 0, 1));
const GeneratedSrpSetupFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_generatedsrpsetup_free(ptr >>> 0, 1));
const HttpClientFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_httpclient_free(ptr >>> 0, 1));
const HttpErrorFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_httperror_free(ptr >>> 0, 1));
const SrpCredentialsFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_srpcredentials_free(ptr >>> 0, 1));
const SrpSessionFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_srpsession_free(ptr >>> 0, 1));

function addToExternrefTable0(obj) {
    const idx = wasm.__externref_table_alloc();
    wasm.__wbindgen_externrefs.set(idx, obj);
    return idx;
}

const CLOSURE_DTORS = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(state => state.dtor(state.a, state.b));

function debugString(val) {
    // primitive types
    const type = typeof val;
    if (type == 'number' || type == 'boolean' || val == null) {
        return  `${val}`;
    }
    if (type == 'string') {
        return `"${val}"`;
    }
    if (type == 'symbol') {
        const description = val.description;
        if (description == null) {
            return 'Symbol';
        } else {
            return `Symbol(${description})`;
        }
    }
    if (type == 'function') {
        const name = val.name;
        if (typeof name == 'string' && name.length > 0) {
            return `Function(${name})`;
        } else {
            return 'Function';
        }
    }
    // objects
    if (Array.isArray(val)) {
        const length = val.length;
        let debug = '[';
        if (length > 0) {
            debug += debugString(val[0]);
        }
        for(let i = 1; i < length; i++) {
            debug += ', ' + debugString(val[i]);
        }
        debug += ']';
        return debug;
    }
    // Test for built-in
    const builtInMatches = /\[object ([^\]]+)\]/.exec(toString.call(val));
    let className;
    if (builtInMatches && builtInMatches.length > 1) {
        className = builtInMatches[1];
    } else {
        // Failed to match the standard '[object ClassName]'
        return toString.call(val);
    }
    if (className == 'Object') {
        // we're a user defined class or Object
        // JSON.stringify avoids problems with cycles, and is generally much
        // easier than looping through ownProperties of `val`.
        try {
            return 'Object(' + JSON.stringify(val) + ')';
        } catch (_) {
            return 'Object';
        }
    }
    // errors
    if (val instanceof Error) {
        return `${val.name}: ${val.message}\n${val.stack}`;
    }
    // TODO we could test for more things here, like `Set`s and `Map`s.
    return className;
}

function getArrayU8FromWasm0(ptr, len) {
    ptr = ptr >>> 0;
    return getUint8ArrayMemory0().subarray(ptr / 1, ptr / 1 + len);
}

let cachedDataViewMemory0 = null;
function getDataViewMemory0() {
    if (cachedDataViewMemory0 === null || cachedDataViewMemory0.buffer.detached === true || (cachedDataViewMemory0.buffer.detached === undefined && cachedDataViewMemory0.buffer !== wasm.memory.buffer)) {
        cachedDataViewMemory0 = new DataView(wasm.memory.buffer);
    }
    return cachedDataViewMemory0;
}

function getStringFromWasm0(ptr, len) {
    ptr = ptr >>> 0;
    return decodeText(ptr, len);
}

let cachedUint8ArrayMemory0 = null;
function getUint8ArrayMemory0() {
    if (cachedUint8ArrayMemory0 === null || cachedUint8ArrayMemory0.byteLength === 0) {
        cachedUint8ArrayMemory0 = new Uint8Array(wasm.memory.buffer);
    }
    return cachedUint8ArrayMemory0;
}

function handleError(f, args) {
    try {
        return f.apply(this, args);
    } catch (e) {
        const idx = addToExternrefTable0(e);
        wasm.__wbindgen_exn_store(idx);
    }
}

function isLikeNone(x) {
    return x === undefined || x === null;
}

function makeMutClosure(arg0, arg1, dtor, f) {
    const state = { a: arg0, b: arg1, cnt: 1, dtor };
    const real = (...args) => {

        // First up with a closure we increment the internal reference
        // count. This ensures that the Rust closure environment won't
        // be deallocated while we're invoking it.
        state.cnt++;
        const a = state.a;
        state.a = 0;
        try {
            return f(a, state.b, ...args);
        } finally {
            state.a = a;
            real._wbg_cb_unref();
        }
    };
    real._wbg_cb_unref = () => {
        if (--state.cnt === 0) {
            state.dtor(state.a, state.b);
            state.a = 0;
            CLOSURE_DTORS.unregister(state);
        }
    };
    CLOSURE_DTORS.register(real, state, state);
    return real;
}

function passArray8ToWasm0(arg, malloc) {
    const ptr = malloc(arg.length * 1, 1) >>> 0;
    getUint8ArrayMemory0().set(arg, ptr / 1);
    WASM_VECTOR_LEN = arg.length;
    return ptr;
}

function passStringToWasm0(arg, malloc, realloc) {
    if (realloc === undefined) {
        const buf = cachedTextEncoder.encode(arg);
        const ptr = malloc(buf.length, 1) >>> 0;
        getUint8ArrayMemory0().subarray(ptr, ptr + buf.length).set(buf);
        WASM_VECTOR_LEN = buf.length;
        return ptr;
    }

    let len = arg.length;
    let ptr = malloc(len, 1) >>> 0;

    const mem = getUint8ArrayMemory0();

    let offset = 0;

    for (; offset < len; offset++) {
        const code = arg.charCodeAt(offset);
        if (code > 0x7F) break;
        mem[ptr + offset] = code;
    }
    if (offset !== len) {
        if (offset !== 0) {
            arg = arg.slice(offset);
        }
        ptr = realloc(ptr, len, len = offset + arg.length * 3, 1) >>> 0;
        const view = getUint8ArrayMemory0().subarray(ptr + offset, ptr + len);
        const ret = cachedTextEncoder.encodeInto(arg, view);

        offset += ret.written;
        ptr = realloc(ptr, len, offset, 1) >>> 0;
    }

    WASM_VECTOR_LEN = offset;
    return ptr;
}

function takeFromExternrefTable0(idx) {
    const value = wasm.__wbindgen_externrefs.get(idx);
    wasm.__externref_table_dealloc(idx);
    return value;
}

let cachedTextDecoder = new TextDecoder('utf-8', { ignoreBOM: true, fatal: true });
cachedTextDecoder.decode();
const MAX_SAFARI_DECODE_BYTES = 2146435072;
let numBytesDecoded = 0;
function decodeText(ptr, len) {
    numBytesDecoded += len;
    if (numBytesDecoded >= MAX_SAFARI_DECODE_BYTES) {
        cachedTextDecoder = new TextDecoder('utf-8', { ignoreBOM: true, fatal: true });
        cachedTextDecoder.decode();
        numBytesDecoded = len;
    }
    return cachedTextDecoder.decode(getUint8ArrayMemory0().subarray(ptr, ptr + len));
}

const cachedTextEncoder = new TextEncoder();

if (!('encodeInto' in cachedTextEncoder)) {
    cachedTextEncoder.encodeInto = function (arg, view) {
        const buf = cachedTextEncoder.encode(arg);
        view.set(buf);
        return {
            read: arg.length,
            written: buf.length
        };
    };
}

let WASM_VECTOR_LEN = 0;


let wasm;
export function __wbg_set_wasm(val) {
    wasm = val;
}
