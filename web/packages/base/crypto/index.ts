/**
 * @file Cryptographic operations. This is the highest layer of the crypto code
 * hierarchy, and is meant to be used directly by the rest of our code.
 *
 * --|
 * --> For each function, more detailed documentation is in `libsodium.ts` <-
 * --|
 *
 * [Note: Crypto code hierarchy]
 *
 * 1. ente-base/crypto            (Crypto API for our code)
 * 2. ente-base/crypto/libsodium  (The actual implementation)
 * 3. libsodium-wrappers          (JavaScript bindings to libsodium)
 *
 * Our cryptography primitives are provided by libsodium, specifically, its
 * JavaScript bindings ("libsodium-wrappers"). That is the lowest layer.
 *
 * > Note that we use the sumo variant, "libsodium-wrappers-sumo", since the
 *   standard variant does not provide the `crypto_pwhash_*` functions.
 *
 * Direct usage of "libsodium-wrappers" is restricted to `crypto/libsodium.ts`.
 * That is the next higher layer. Usually the functions in this file are thin
 * wrappers over the raw libsodium APIs, with a bit of massaging. They also
 * ensure that sodium.ready has been called before accessing libsodium's APIs,
 * thus all the functions it exposes are async.
 *
 * Direct usage of "libsodium-wrappers" is restricted to this file,
 * `crypto/index.ts`. This is the highest layer. These are direct proxies to
 * functions exposed by `crypto/libsodium.ts`, but they automatically defer to a
 * worker thread if we're not already running on one. More on this below.
 *
 * ---
 *
 * [Note: Using libsodium in worker thread]
 *
 * This file, `crypto/index.ts`, and `crypto/worker.ts` are mostly logic-less
 * trampolines meant to allow us to seamlessly use the the same API both from
 * the main thread or from a web worker whilst ensuring that the implementation
 * never runs on the main thread.
 *
 * Cryptographic operations like encryption are CPU intensive and would cause
 * the UI to stutter if used directly on the main thread. To keep the UI smooth,
 * we instead want to run them in a web worker. However, sometimes we already
 * _are_ running in a web worker, and delegating to another worker is wasteful.
 *
 * The external API functions provided by this file check to see if we're
 * already in a web worker, and if so directly invoke the implementation.
 * Otherwise the call the sibling function in a shared "crypto" web worker
 * (which then invokes the implementation function, but this time in the context
 * of a web worker).
 *
 * As a consumer, it is safe to just call functions in this file, and they'll
 * just do the right thing based on the context. However, it is also fine to
 * explicitly get an handle to a crypto web worker and use that. e.g., the
 * uploader creates it own crypto worker instances and directly calls the
 * functions in the workers that it created instead of going through this file.
 *
 * ---
 *
 * [Note: Crypto layer API data types]
 *
 * There are two primary types used when exchanging data with these functions:
 *
 * 1. Base64 strings. Unless stated otherwise, all strings are taken as base64
 *    encoded representations of the underlying data. Usually, the unqualified
 *    function deals with base64 strings, since they also are the data type in
 *    which we usually store and send the data.
 *
 * 2. Raw bytes. Uint8Arrays are byte arrays. The functions that deal with bytes
 *    are usually indicated by a *Bytes suffix in their name, but not always
 *    since it might also be the natural choice for functions that deal with
 *    larger amounts of data.
 *
 * Where relevant and useful, functions also accept a union of these two - a
 * {@link BytesOrB64} where the implementation will automatically convert
 * to/from base64 to bytes if needed, thus saving on unnecessary conversions at
 * the caller side.
 *
 * Apart from these two, there are other secondary, one off types.
 *
 * 1. Hex representations of the bytes. These are indicated by the *Hex suffix
 *    on the functions dealing with them.
 *
 * 2. JSON values. These are indicated by the *JSON suffix on the functions
 *    dealing with them.
 */
import { ComlinkWorker } from "ente-base/worker/comlink-worker";
import { inWorker } from "../env";
import * as libsodium from "./libsodium";
import type {
    BytesOrB64,
    DerivedKey,
    EncryptedBlob,
    EncryptedBlobB64,
    EncryptedBlobBytes,
    EncryptedBox,
    EncryptedBoxB64,
    EncryptedFile,
    InitChunkDecryptionResult,
    InitChunkEncryptionResult,
    KeyPair,
    SodiumStateAddress,
} from "./types";
import type { CryptoWorker } from "./worker";

/**
 * Cached instance of the {@link ComlinkWorker} that wraps our web worker.
 */
let _comlinkWorker: ComlinkWorker<typeof CryptoWorker> | undefined;

/**
 * Lazily created, cached, instance of a "shared" CryptoWorker web worker.
 *
 * Some code which needs to do operations in parallel (e.g. during the upload
 * flow) creates its own CryptoWorker web workers. But those are exceptions; the
 * rest of the code normally calls the functions in this file, and they all
 * implicitly use a default "shared" web worker (unless we're already running in
 * the context of a web worker).
 */
const sharedWorker = () =>
    (_comlinkWorker ??= createComlinkCryptoWorker()).remote;

/**
 * Create a new instance of a comlink worker that wraps a {@link CryptoWorker}
 * web worker.
 */
export const createComlinkCryptoWorker = () =>
    new ComlinkWorker<typeof CryptoWorker>(
        "crypto",
        new Worker(new URL("worker.ts", import.meta.url)),
    );

/**
 * Convert bytes ({@link Uint8Array}) to a base64 string.
 */
export const toB64 = (bytes: Uint8Array): Promise<string> =>
    inWorker()
        ? libsodium.toB64(bytes)
        : sharedWorker().then((w) => w.toB64(bytes));

/**
 * Convert a base64 string to bytes ({@link Uint8Array}).
 */
export const fromB64 = (b64String: string): Promise<Uint8Array> =>
    inWorker()
        ? libsodium.fromB64(b64String)
        : sharedWorker().then((w) => w.fromB64(b64String));

/**
 * URL safe variant of {@link toB64}.
 */
export const toB64URLSafe = (bytes: Uint8Array): Promise<string> =>
    inWorker()
        ? libsodium.toB64URLSafe(bytes)
        : sharedWorker().then((w) => w.toB64URLSafe(bytes));

/**
 * URL safe variant of {@link toB64} that does not add any padding ("="
 * characters).
 */
export const toB64URLSafeNoPadding = (bytes: Uint8Array): Promise<string> =>
    inWorker()
        ? libsodium.toB64URLSafeNoPadding(bytes)
        : sharedWorker().then((w) => w.toB64URLSafeNoPadding(bytes));

/**
 * URL safe unpadded variant of {@link fromB64}.
 */
export const fromB64URLSafeNoPadding = (
    b64String: string,
): Promise<Uint8Array> =>
    inWorker()
        ? libsodium.fromB64URLSafeNoPadding(b64String)
        : sharedWorker().then((w) => w.fromB64URLSafeNoPadding(b64String));

/**
 * Convert a base64 string to the hex representation of the underlying bytes.
 */
export const toHex = (b64String: string): Promise<string> =>
    inWorker()
        ? libsodium.toHex(b64String)
        : sharedWorker().then((w) => w.toHex(b64String));

/**
 * Convert a hex string to the base64 representation of the underlying bytes.
 */
export const fromHex = (hexString: string): Promise<string> =>
    inWorker()
        ? libsodium.fromHex(hexString)
        : sharedWorker().then((w) => w.fromHex(hexString));

/**
 * Return a new randomly generated 256-bit key (as a base64 string).
 *
 * The returned key is suitable for use with the *Box encryption functions, and
 * as a general encryption key (e.g. as the user's master key or recovery key).
 */
export const generateKey = (): Promise<string> =>
    inWorker()
        ? libsodium.generateKey()
        : sharedWorker().then((w) => w.generateKey());

/**
 * Return a new randomly generated 256-bit key (as a base64 string) suitable for
 * use with the *Blob or *Stream encryption functions.
 */
export const generateBlobOrStreamKey = (): Promise<string> =>
    inWorker()
        ? libsodium.generateBlobOrStreamKey()
        : sharedWorker().then((w) => w.generateBlobOrStreamKey());

/**
 * Encrypt the given data, returning a box containing the encrypted data and a
 * randomly generated nonce that was used during encryption.
 *
 * Both the encrypted data and the nonce are returned as base64 strings.
 *
 * Use {@link decryptBox} to decrypt the result.
 *
 * > The suffix "Box" comes from the fact that it uses the so called secretbox
 * > APIs provided by libsodium under the hood.
 * >
 * > See: [Note: 3 forms of encryption (Box | Blob | Stream)]
 */
export const encryptBox = (
    data: BytesOrB64,
    key: BytesOrB64,
): Promise<EncryptedBoxB64> =>
    inWorker()
        ? libsodium.encryptBox(data, key)
        : sharedWorker().then((w) => w.encryptBox(data, key));

/**
 * Encrypt the given data, returning a blob containing the encrypted data and a
 * decryption header as base64 strings.
 *
 * This function is usually used to encrypt data associated with an Ente object
 * (file, collection, entity) using the object's key.
 *
 * Use {@link decryptBlob} or {@link decryptBlobBytes} to decrypt the result.
 *
 * > The suffix "Blob" comes from our convention of naming functions that use
 * > the secretstream APIs without breaking the data into chunks.
 * >
 * > See: [Note: 3 forms of encryption (Box | Blob | Stream)]
 */
export const encryptBlob = (
    data: BytesOrB64,
    key: BytesOrB64,
): Promise<EncryptedBlobB64> =>
    inWorker()
        ? libsodium.encryptBlob(data, key)
        : sharedWorker().then((w) => w.encryptBlob(data, key));

/**
 * A variant of {@link encryptBlob} that returns the result components as bytes
 * instead of as base64 strings.
 *
 * Use {@link decryptBlob} or {@link decryptBlobBytes} to decrypt the result.
 */
export const encryptBlobBytes = (
    data: BytesOrB64,
    key: BytesOrB64,
): Promise<EncryptedBlobBytes> =>
    inWorker()
        ? libsodium.encryptBlobBytes(data, key)
        : sharedWorker().then((w) => w.encryptBlobBytes(data, key));

/**
 * Encrypt the JSON metadata associated with an Ente object (file, collection or
 * entity) using the object's key.
 *
 * This is a variant of {@link encryptBlob} tailored for encrypting any
 * arbitrary metadata associated with an Ente object. For example, it is used
 * for encrypting the various metadata fields associated with a file, using that
 * file's key.
 *
 * Instead of raw bytes, it takes as input an arbitrary JSON object which it
 * encodes into a string, and encrypts that.
 *
 * Use {@link decryptMetadataJSON} to decrypt the result.
 *
 * @param jsonValue The JSON value to encrypt. This can be an arbitrary JSON
 * value, but since TypeScript currently doesn't have a native JSON type, it is
 * typed as {@link unknown}.
 *
 * @param key The encryption key.
 */
export const encryptMetadataJSON = (
    jsonValue: unknown,
    key: BytesOrB64,
): Promise<EncryptedBlobB64> =>
    inWorker()
        ? libsodium.encryptMetadataJSON(jsonValue, key)
        : sharedWorker().then((w) => w.encryptMetadataJSON(jsonValue, key));

/**
 * Encrypt the given data using chunked streaming encryption, but process all
 * the chunks in one go.
 */
export const encryptStreamBytes = (
    data: Uint8Array,
    key: BytesOrB64,
): Promise<EncryptedFile> =>
    inWorker()
        ? libsodium.encryptStreamBytes(data, key)
        : sharedWorker().then((w) => w.encryptStreamBytes(data, key));

/**
 * Prepare for chunked streaming encryption using {@link encryptStreamChunk}.
 */
export const initChunkEncryption = (
    key: BytesOrB64,
): Promise<InitChunkEncryptionResult> =>
    inWorker()
        ? libsodium.initChunkEncryption(key)
        : sharedWorker().then((w) => w.initChunkEncryption(key));

/**
 * Encrypt a chunk as part of a chunked streaming encryption.
 */
export const encryptStreamChunk = (
    data: Uint8Array,
    state: SodiumStateAddress,
    isFinalChunk: boolean,
): Promise<Uint8Array<ArrayBuffer>> =>
    inWorker()
        ? libsodium.encryptStreamChunk(data, state, isFinalChunk)
        : sharedWorker().then((w) =>
              w.encryptStreamChunk(data, state, isFinalChunk),
          );

/**
 * Decrypt a box encrypted using {@link encryptBox} and returns the decrypted
 * bytes as a base64 string.
 */
export const decryptBox = (
    box: EncryptedBox,
    key: BytesOrB64,
): Promise<string> =>
    inWorker()
        ? libsodium.decryptBox(box, key)
        : sharedWorker().then((w) => w.decryptBox(box, key));

/**
 * Variant of {@link decryptBox} that returns the decrypted bytes as it is
 * (without encoding them to base64).
 */
export const decryptBoxBytes = (
    box: EncryptedBox,
    key: BytesOrB64,
): Promise<Uint8Array<ArrayBuffer>> =>
    inWorker()
        ? libsodium.decryptBoxBytes(box, key)
        : sharedWorker().then((w) => w.decryptBoxBytes(box, key));

/**
 * Decrypt a blob encrypted using either {@link encryptBlobBytes} or
 * {@link encryptBlob} and return it as a base64 encoded string.
 */
export const decryptBlob = (
    blob: EncryptedBlob,
    key: BytesOrB64,
): Promise<string> =>
    inWorker()
        ? libsodium.decryptBlob(blob, key)
        : sharedWorker().then((w) => w.decryptBlob(blob, key));

/**
 * A variant of {@link decryptBlobBytes} that returns the result bytes directly
 * (instead of encoding them as a base64 string).
 */
export const decryptBlobBytes = (
    blob: EncryptedBlob,
    key: BytesOrB64,
): Promise<Uint8Array<ArrayBuffer>> =>
    inWorker()
        ? libsodium.decryptBlobBytes(blob, key)
        : sharedWorker().then((w) => w.decryptBlobBytes(blob, key));

/**
 * Decrypt the result of {@link encryptStreamBytes}.
 */
export const decryptStreamBytes = (
    file: EncryptedFile,
    key: BytesOrB64,
): Promise<Uint8Array<ArrayBuffer>> =>
    inWorker()
        ? libsodium.decryptStreamBytes(file, key)
        : sharedWorker().then((w) => w.decryptStreamBytes(file, key));

/**
 * Prepare to decrypt the encrypted result produced using {@link initChunkEncryption} and
 * {@link encryptStreamChunk}.
 */
export const initChunkDecryption = (
    header: string,
    key: BytesOrB64,
): Promise<InitChunkDecryptionResult> =>
    inWorker()
        ? libsodium.initChunkDecryption(header, key)
        : sharedWorker().then((w) => w.initChunkDecryption(header, key));

/**
 * Decrypt an individual chunk produced by {@link encryptStreamChunk}.
 *
 * This function is used in tandem with {@link initChunkDecryption}.
 */
export const decryptStreamChunk = (
    data: Uint8Array,
    state: SodiumStateAddress,
): Promise<Uint8Array<ArrayBuffer>> =>
    inWorker()
        ? libsodium.decryptStreamChunk(data, state)
        : sharedWorker().then((w) => w.decryptStreamChunk(data, state));

/**
 * Decrypt the metadata JSON encrypted using {@link encryptMetadataJSON}.
 *
 * @returns The decrypted JSON value. Since TypeScript does not have a native
 * JSON type, we need to return it as an `unknown`.
 */
export const decryptMetadataJSON = (
    blob: EncryptedBlob,
    key: BytesOrB64,
): Promise<unknown> =>
    inWorker()
        ? libsodium.decryptMetadataJSON(blob, key)
        : sharedWorker().then((w) => w.decryptMetadataJSON(blob, key));

/**
 * Generate a new public/private keypair.
 */
export const generateKeyPair = (): Promise<KeyPair> =>
    inWorker()
        ? libsodium.generateKeyPair()
        : sharedWorker().then((w) => w.generateKeyPair());

/**
 * Public key encryption.
 */
export const boxSeal = (data: string, publicKey: string): Promise<string> =>
    inWorker()
        ? libsodium.boxSeal(data, publicKey)
        : sharedWorker().then((w) => w.boxSeal(data, publicKey));

/**
 * Decrypt the result of {@link boxSeal}.
 */
export const boxSealOpen = (
    encryptedData: string,
    keyPair: KeyPair,
): Promise<string> =>
    inWorker()
        ? libsodium.boxSealOpen(encryptedData, keyPair)
        : sharedWorker().then((w) => w.boxSealOpen(encryptedData, keyPair));

/**
 * Variant of {@link boxSealOpen} that returns the decrypted bytes as it is
 * (without encoding them to base64).
 */
export const boxSealOpenBytes = (
    encryptedData: string,
    keyPair: KeyPair,
): Promise<Uint8Array> =>
    inWorker()
        ? libsodium.boxSealOpenBytes(encryptedData, keyPair)
        : sharedWorker().then((w) =>
              w.boxSealOpenBytes(encryptedData, keyPair),
          );

/**
 * Return a new randomly generated 128-bit salt (as a base64 string).
 *
 * The returned salt is suitable for use with {@link deriveKey}, and also as a
 * general 128-bit salt.
 */
export const generateDeriveKeySalt = (): Promise<string> =>
    inWorker()
        ? libsodium.generateDeriveKeySalt()
        : sharedWorker().then((w) => w.generateDeriveKeySalt());

/**
 * Derive a key by hashing the given {@link passphrase} using Argon 2id.
 */
export const deriveKey = (
    passphrase: string,
    salt: string,
    opsLimit: number,
    memLimit: number,
): Promise<string> =>
    inWorker()
        ? libsodium.deriveKey(passphrase, salt, opsLimit, memLimit)
        : sharedWorker().then((w) =>
              w.deriveKey(passphrase, salt, opsLimit, memLimit),
          );

/**
 * Derive a sensitive key from the given {@link passphrase}.
 */
export const deriveSensitiveKey = (passphrase: string): Promise<DerivedKey> =>
    inWorker()
        ? libsodium.deriveSensitiveKey(passphrase)
        : sharedWorker().then((w) => w.deriveSensitiveKey(passphrase));

/**
 * Derive an key suitable for interactive use from the given {@link passphrase}.
 */
export const deriveInteractiveKey = (
    passphrase: string,
): Promise<DerivedKey> =>
    inWorker()
        ? libsodium.deriveInteractiveKey(passphrase)
        : sharedWorker().then((w) => w.deriveInteractiveKey(passphrase));

/**
 * Derive a key suitable for moderate-cost password gates from the given
 * {@link passphrase}.
 */
export const deriveModerateKey = (passphrase: string): Promise<DerivedKey> =>
    inWorker()
        ? libsodium.deriveModerateKey(passphrase)
        : sharedWorker().then((w) => w.deriveModerateKey(passphrase));

/**
 * Derive a subkey of the given {@link key} using the specified parameters.
 *
 * @returns the bytes of the derived subkey.
 */
export const deriveSubKeyBytes = async (
    key: string,
    subKeyLength: number,
    subKeyID: number,
    context: string,
): Promise<Uint8Array> =>
    inWorker()
        ? libsodium.deriveSubKeyBytes(key, subKeyLength, subKeyID, context)
        : sharedWorker().then((w) =>
              w.deriveSubKeyBytes(key, subKeyLength, subKeyID, context),
          );
