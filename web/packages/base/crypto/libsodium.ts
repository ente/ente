/**
 * @file A thin-ish layer over the actual libsodium APIs, to make them more
 * palatable to the rest of our Javascript code.
 *
 * All functions are stateless, async, and safe to use in Web Workers.
 *
 * Docs for the JS library: https://github.com/jedisct1/libsodium.js.
 *
 * To see where this code fits, see [Note: Crypto code hierarchy].
 */
import { ensureArrayBufferBacked } from "ente-base/bytes";
import { mergeUint8Arrays } from "ente-utils/array";
import sodium from "libsodium-wrappers-sumo";
import {
    deriveKeyInsufficientMemoryErrorMessage,
    streamEncryptionChunkSize,
    type BytesOrB64,
    type DerivedKey,
    type EncryptedBlob,
    type EncryptedBlobB64,
    type EncryptedBlobBytes,
    type EncryptedBox,
    type EncryptedBoxB64,
    type EncryptedFile,
    type InitChunkDecryptionResult,
    type InitChunkEncryptionResult,
    type KeyPair,
    type SodiumStateAddress,
} from "./types";

/**
 * Convert bytes ({@link Uint8Array}) to a base64 string.
 *
 * See also {@link toB64URLSafe} and {@link toB64URLSafeNoPadding}.
 */
export const toB64 = async (input: Uint8Array) => {
    await sodium.ready;
    return sodium.to_base64(input, sodium.base64_variants.ORIGINAL);
};

/**
 * Convert a base64 string to bytes ({@link Uint8Array}).
 *
 * This is the converse of {@link toBase64}.
 */
export const fromB64 = async (
    input: string,
): Promise<Uint8Array<ArrayBuffer>> => {
    await sodium.ready;
    return ensureArrayBufferBacked(
        sodium.from_base64(input, sodium.base64_variants.ORIGINAL),
    );
};

/**
 * Convert bytes ({@link Uint8Array}) to a URL-safe base64 string.
 *
 * See also {@link toB64URLSafe} and {@link toB64URLSafeNoPadding}.
 */
export const toB64URLSafe = async (input: Uint8Array) => {
    await sodium.ready;
    return sodium.to_base64(input, sodium.base64_variants.URLSAFE);
};

/**
 * Convert bytes ({@link Uint8Array}) to a unpadded URL-safe base64 string.
 *
 * This differs from {@link toB64URLSafe} in that it does not append any
 * trailing padding character(s) "=" to make the resultant string's length be an
 * integer multiple of 4.
 *
 * - In some contexts, for example when serializing WebAuthn binary for
 *   transmission over the network, this is the required / recommended approach.
 *
 * - In other cases, for example when trying to pass an arbitrary JSON string
 *   via a URL parameter, this is also convenient so that we do not have to deal
 *   with any ambiguity surrounding the "=" which is also the query parameter
 *   key value separator.
 */
export const toB64URLSafeNoPadding = async (input: Uint8Array) => {
    await sodium.ready;
    return sodium.to_base64(input, sodium.base64_variants.URLSAFE_NO_PADDING);
};

/**
 * Convert a unpadded URL-safe base64 string to  bytes ({@link Uint8Array}).
 *
 * This is the converse of {@link toB64URLSafeNoPadding}, and does not expect
 * its input string's length to be a an integer multiple of 4.
 */
export const fromB64URLSafeNoPadding = async (
    input: string,
): Promise<Uint8Array<ArrayBuffer>> => {
    await sodium.ready;
    return ensureArrayBufferBacked(
        sodium.from_base64(input, sodium.base64_variants.URLSAFE_NO_PADDING),
    );
};

/**
 * Convert a base64 string to the hex representation of the bytes that the base
 * 64 string encodes.
 *
 * Use {@link fromHex} to go back.
 */
export const toHex = async (input: string) => {
    await sodium.ready;
    return sodium.to_hex(await fromB64(input));
};

/**
 * Convert a hex string to the base64 representation of the bytes that the hex
 * string encodes.
 *
 * This is the inverse of {@link toHex}.
 */
export const fromHex = async (input: string): Promise<string> => {
    await sodium.ready;
    return await toB64(sodium.from_hex(input));
};

/**
 * If the provided {@link bob} ("Bytes or B64 string") is already a
 * {@link Uint8Array}, return it unchanged, otherwise convert the base64 string
 * into bytes and return those.
 */
const bytes = async (bob: BytesOrB64) =>
    typeof bob == "string" ? fromB64(bob) : bob;

/**
 * Generate a new randomly generated 256-bit key for use as a general encryption
 * key and return its base64 string representation.
 *
 * From the architecture docs:
 *
 * > [`crypto_secretbox_keygen`](https://libsodium.gitbook.io/doc/public-key_cryptography/sealed_boxes)
 * > is used to generate all random keys within the application. Your
 * > `masterKey`, `recoveryKey`, `collectionKey`, `fileKey` are all 256-bit keys
 * > generated using this API.
 *
 * {@link generateKey} can be contrasted with {@link generateBlobOrStreamKey}
 * and can be thought of as a hypothetical "generateBoxKey". That is, the key
 * returned by this function is suitable for being used with the *Box encryption
 * functions (which eventually delegate to the libsodium's secretbox APIs).
 *
 * While this is a reasonable semantic distinction, in terms of implementation
 * there is no difference: currently both {@link generateKey} (or the
 * hypothetical "generateBoxKey") and {@link generateBlobOrStreamKey} produce
 * 256-bits of entropy that does not have any ties to a particular algorithm.
 *
 * @returns A new randomly generated 256-bit key (as a base64 string).
 */
export const generateKey = async () => {
    await sodium.ready;
    return toB64(sodium.crypto_secretbox_keygen());
};

/**
 * Generate a new key for use with the *Blob or *Stream encryption functions,
 * and return its base64 string representation.
 *
 * This returns a new randomly generated 256-bit key (as a base64 string)
 * suitable for being used with libsodium's secretstream APIs.
 */
export const generateBlobOrStreamKey = async () => {
    await sodium.ready;
    return toB64(sodium.crypto_secretstream_xchacha20poly1305_keygen());
};

/**
 * Encrypt the given data using libsodium's secretbox APIs, using a randomly
 * generated nonce.
 *
 * Use {@link decryptBox} or {@link decryptBoxBytes} to decrypt the result.
 *
 * @param data The data to encrypt.
 *
 * @param key The key to use for encryption.
 *
 * @returns The encrypted data and the generated nonce, both as base64 strings.
 *
 * [Note: 3 forms of encryption (Box | Blob | Stream)]
 *
 * libsodium provides two "high level" encryption patterns:
 *
 * 1. Authenticated encryption ("secretbox")
 *    https://doc.libsodium.org/secret-key_cryptography/secretbox
 *
 * 2. Encrypted streams and file encryption ("secretstream")
 *    https://doc.libsodium.org/secret-key_cryptography/secretstream
 *
 * In terms of the underlying algorithm, they are essentially the same.
 *
 * 1. The secretbox APIs use XSalsa20 with Poly1305 (where XSalsa20 is the
 *    stream cipher used for encryption, which Poly1305 is the MAC used for
 *    authentication).
 *
 * 2. The secretstream APIs use XChaCha20 with Poly1305.
 *
 * XSalsa20 is a minor variant (predecessor in fact) of XChaCha20. I am not
 * aware why libsodium uses both the variants, but they seem to have similar
 * characteristics.
 *
 * These two sets of APIs map functionally map to two different use cases.
 *
 * 1. If there is a single independent bit of data to encrypt, the secretbox
 *    APIs fit the bill.
 *
 * 2. If there is a set of related data to encrypt, e.g. the contents of a file
 *    where the file is too big to fit into a single message, then the
 *    secretstream APIs are more appropriate.
 *
 * However, in our code we have evolved two different use cases for the 2nd
 * option. The data to encrypt might be smaller than our streaming encryption
 * chunk size (e.g. the public magic metadata associated with the
 * {@link EnteFile}), so we do not chunk it and instead encrypt / decrypt it in
 * a single go. In contrast, the actual file that the user wishes to upload may
 * be arbitrarily big, and there we first break in into chunks before using the
 * streaming encryption.
 *
 * Thus, we have three scenarios:
 *
 * 1. Box: Using secretbox APIs to encrypt some independent blob of data.
 *
 * 2. Blob: Using secretstream APIs without chunking. This is used to encrypt
 *    data associated to an Ente object (file, collection, entity, etc), when
 *    the data is small-ish (less than a few MBs).
 *
 * 3. Stream/Chunks: Using secretstream APIs for encrypting chunks. This is used
 *    to encrypt the actual content of the files associated with an EnteFile
 *    object. This itself happens in two ways:
 *
 *     3a. One shot mode - where we do break the data into chunks, but a single
 *         function processes all the chunks in one go.
 *
 *     3b. Streaming - where all the chunks are processed one by one.
 *
 * "Blob" is not a prior term of art in this context, it is just something we
 * use to abbreviate "data encrypted using secretstream APIs without chunking".
 *
 * The distinction between Box and Blob is also handy since not only does the
 * underlying algorithm differ, but also the terminology that libsodium use for
 * the nonce.
 *
 * 1. When using the secretbox APIs, the nonce is called the "nonce", and needs
 *    to be provided by us (the caller).
 *
 * 2. When using the secretstream APIs, the nonce is internally generated by
 *    libsodium and provided by libsodium to us (the caller) as a "header".
 *
 * However, even for case 1, the functions we expose from libsodium.ts generate
 * the nonce for the caller. So for higher level functions, the difference
 * between Box and Blob encryption is:
 *
 * 1. Box uses secretbox APIs (Salsa), Blob uses secretstream APIs (ChaCha).
 *
 * 2. Blob should generally be used for data associated with an Ente object, and
 *    Box for the other cases.
 *
 * 3. Box returns a "nonce", while Blob returns a "header".
 *
 * The difference between case 2 and 3 (Blob vs Stream) is that while both use
 * the same algorithms, in case of Blob the entire data is encrypted / decrypted
 * without chunking, whilst the *Stream routines first break it into
 * {@link streamEncryptionChunkSize} chunks.
 */
export const encryptBox = async (
    data: BytesOrB64,
    key: BytesOrB64,
): Promise<EncryptedBoxB64> => {
    await sodium.ready;
    const nonce = sodium.randombytes_buf(sodium.crypto_secretbox_NONCEBYTES);
    const encryptedData = sodium.crypto_secretbox_easy(
        await bytes(data),
        nonce,
        await bytes(key),
    );
    return {
        encryptedData: await toB64(encryptedData),
        nonce: await toB64(nonce),
    };
};

/**
 * Encrypt the given data using libsodium's secretstream APIs without chunking.
 *
 * Use {@link decryptBlobBytes} to decrypt the result.
 *
 * @param data The data to encrypt.
 *
 * @param key The key to use for encryption.
 *
 * @returns The encrypted data and the decryption header as {@link Uint8Array}s.
 *
 * - See: [Note: 3 forms of encryption (Box | Blob | Stream)].
 *
 * - See: https://doc.libsodium.org/secret-key_cryptography/secretstream
 */
export const encryptBlobBytes = async (
    data: BytesOrB64,
    key: BytesOrB64,
): Promise<EncryptedBlobBytes> => {
    await sodium.ready;

    const keyBytes = await bytes(key);
    const initPushResult =
        sodium.crypto_secretstream_xchacha20poly1305_init_push(keyBytes);
    const [pushState, header] = [initPushResult.state, initPushResult.header];

    const pushResult = sodium.crypto_secretstream_xchacha20poly1305_push(
        pushState,
        await bytes(data),
        null,
        sodium.crypto_secretstream_xchacha20poly1305_TAG_FINAL,
    );
    return {
        encryptedData: ensureArrayBufferBacked(pushResult),
        decryptionHeader: ensureArrayBufferBacked(header),
    };
};

/**
 * A higher level variant of {@link encryptBlobBytes} that returns the both the
 * encrypted data and decryption header as base64 strings.
 *
 * This is the variant expected to serve majority of the public API use cases.
 */
export const encryptBlob = async (
    data: BytesOrB64,
    key: BytesOrB64,
): Promise<EncryptedBlobB64> => {
    const { encryptedData, decryptionHeader } = await encryptBlobBytes(
        data,
        key,
    );
    return {
        encryptedData: await toB64(encryptedData),
        decryptionHeader: await toB64(decryptionHeader),
    };
};

/**
 * Encrypt the provided JSON value (using {@link encryptBlob}) after converting
 * it to a JSON string (and UTF-8 encoding it to obtain bytes).
 *
 * Use {@link decryptMetadataJSON} to decrypt the result and convert it back to
 * a JSON value.
 */
export const encryptMetadataJSON = (
    jsonValue: unknown,
    key: BytesOrB64,
): Promise<EncryptedBlobB64> =>
    encryptBlob(new TextEncoder().encode(JSON.stringify(jsonValue)), key);

/**
 * Encrypt the given data using libsodium's secretstream APIs after breaking it
 * into {@link streamEncryptionChunkSize} chunks.
 *
 * Use {@link decryptStreamBytes} to decrypt the result.
 *
 * Unlike {@link initChunkDecryption} / {@link encryptFileChunk}, this function
 * processes all the chunks at once in a single call to this function.
 *
 * @param data The data to encrypt.
 *
 * @returns The encrypted bytes ({@link Uint8Array}) and the decryption header
 * (as a base64 string).
 *
 * - See: [Note: 3 forms of encryption (Box | Blob | Stream)].
 *
 * - See: https://doc.libsodium.org/secret-key_cryptography/secretstream
 */
export const encryptStreamBytes = async (
    data: Uint8Array,
    key: BytesOrB64,
): Promise<EncryptedFile> => {
    await sodium.ready;

    const keyBytes = await bytes(key);
    const initPushResult =
        sodium.crypto_secretstream_xchacha20poly1305_init_push(keyBytes);
    const [pushState, header] = [initPushResult.state, initPushResult.header];
    let bytesRead = 0;
    let tag = sodium.crypto_secretstream_xchacha20poly1305_TAG_MESSAGE;

    const encryptedChunks = [];

    while (tag !== sodium.crypto_secretstream_xchacha20poly1305_TAG_FINAL) {
        let chunkSize = streamEncryptionChunkSize;
        if (bytesRead + chunkSize >= data.length) {
            chunkSize = data.length - bytesRead;
            tag = sodium.crypto_secretstream_xchacha20poly1305_TAG_FINAL;
        }

        const buffer = data.slice(bytesRead, bytesRead + chunkSize);
        bytesRead += chunkSize;
        const pushResult = sodium.crypto_secretstream_xchacha20poly1305_push(
            pushState,
            buffer,
            null,
            tag,
        );
        encryptedChunks.push(pushResult);
    }
    return {
        encryptedData: mergeUint8Arrays(encryptedChunks),
        decryptionHeader: await toB64(header),
    };
};

/**
 * Initialize libsodium's secretstream APIs for encrypting
 * {@link streamEncryptionChunkSize} chunks. Subsequently, each chunk can be
 * encrypted using {@link encryptStreamChunk}.
 *
 * Use {@link initChunkDecryption} to initialize the decryption routine, and
 * {@link decryptStreamChunk} to decrypt the individual chunks.
 *
 * See also: {@link encryptStreamBytes} which also does chunked encryption but
 * encrypts all the chunks in a single call.
 *
 * @param key The key to use for encryption.
 *
 * @returns The decryption header (as a base64 string) which should be preserved
 * and used during decryption, and an opaque "push state" that should be passed
 * to subsequent calls to {@link encryptStreamChunk} along with the chunks's
 * contents.
 */
export const initChunkEncryption = async (
    key: BytesOrB64,
): Promise<InitChunkEncryptionResult> => {
    await sodium.ready;
    const keyBytes = await bytes(key);
    const { state, header } =
        sodium.crypto_secretstream_xchacha20poly1305_init_push(keyBytes);
    return { decryptionHeader: await toB64(header), pushState: state };
};

/**
 * Encrypt an individual chunk using libsodium's secretstream APIs.
 *
 * This function is not meant to be standalone, but is instead called in tandem
 * with {@link initChunkEncryption} for encrypting data after breaking it into
 * chunks.
 *
 * @param data The chunk's data as bytes ({@link Uint8Array}).
 *
 * @param pushState The state for this instantiation of chunked encryption. This
 * should be treated as opaque libsodium state that should be passed to all
 * calls to {@link encryptStreamChunk} that are paired with a particular
 * {@link initChunkEncryption}.
 *
 * @param isFinalChunk `true` if this is the last chunk in the sequence.
 *
 * @returns The encrypted chunk.
 */
export const encryptStreamChunk = async (
    data: Uint8Array,
    pushState: SodiumStateAddress,
    isFinalChunk: boolean,
): Promise<Uint8Array<ArrayBuffer>> => {
    await sodium.ready;
    const tag = isFinalChunk
        ? sodium.crypto_secretstream_xchacha20poly1305_TAG_FINAL
        : sodium.crypto_secretstream_xchacha20poly1305_TAG_MESSAGE;
    return ensureArrayBufferBacked(
        sodium.crypto_secretstream_xchacha20poly1305_push(
            pushState,
            data,
            null,
            tag,
        ),
    );
};

/**
 * Decrypt the result of {@link encryptBox} and return the decrypted bytes.
 */
export const decryptBoxBytes = async (
    { encryptedData, nonce }: EncryptedBox,
    key: BytesOrB64,
): Promise<Uint8Array<ArrayBuffer>> => {
    await sodium.ready;
    return ensureArrayBufferBacked(
        sodium.crypto_secretbox_open_easy(
            await bytes(encryptedData),
            await bytes(nonce),
            await bytes(key),
        ),
    );
};

/**
 * Variant of {@link decryptBoxBytes} that returns the data as a base64 string.
 */
export const decryptBox = (
    box: EncryptedBox,
    key: BytesOrB64,
): Promise<string> => decryptBoxBytes(box, key).then(toB64);

/**
 * Decrypt the result of {@link encryptBlobBytes} or {@link encryptBlob}.
 */
export const decryptBlobBytes = async (
    { encryptedData, decryptionHeader }: EncryptedBlob,
    key: BytesOrB64,
): Promise<Uint8Array<ArrayBuffer>> => {
    await sodium.ready;
    const pullState = sodium.crypto_secretstream_xchacha20poly1305_init_pull(
        await bytes(decryptionHeader),
        await bytes(key),
    );
    const pullResult = sodium.crypto_secretstream_xchacha20poly1305_pull(
        pullState,
        await bytes(encryptedData),
        null,
    );
    return ensureArrayBufferBacked(pullResult.message);
};

/**
 * A variant of {@link decryptBlobBytes} that returns the result as a base64
 * string.
 */
export const decryptBlob = (
    blob: EncryptedBlob,
    key: BytesOrB64,
): Promise<string> => decryptBlobBytes(blob, key).then(toB64);

/**
 * Decrypt the result of {@link encryptMetadataJSON} and return the JSON value
 * obtained by parsing the decrypted JSON string (which is obtained by UTF-8
 * decoding the decrypted bytes).
 *
 * Since TypeScript doesn't currently have a native JSON type, the returned
 * value is casted as an `unknown`.
 */
export const decryptMetadataJSON = async (
    blob: EncryptedBlob,
    key: BytesOrB64,
): Promise<unknown> =>
    JSON.parse(
        new TextDecoder().decode(await decryptBlobBytes(blob, key)),
    ) as unknown;

/**
 * Decrypt the result of {@link encryptStreamBytes}.
 */
export const decryptStreamBytes = async (
    { encryptedData, decryptionHeader }: EncryptedFile,
    key: BytesOrB64,
): Promise<Uint8Array<ArrayBuffer>> => {
    await sodium.ready;
    const pullState = sodium.crypto_secretstream_xchacha20poly1305_init_pull(
        await fromB64(decryptionHeader),
        await bytes(key),
    );
    const decryptionChunkSize =
        streamEncryptionChunkSize +
        sodium.crypto_secretstream_xchacha20poly1305_ABYTES;
    let bytesRead = 0;
    const decryptedChunks = [];
    let tag = sodium.crypto_secretstream_xchacha20poly1305_TAG_MESSAGE;
    while (tag !== sodium.crypto_secretstream_xchacha20poly1305_TAG_FINAL) {
        let chunkSize = decryptionChunkSize;
        if (bytesRead + chunkSize > encryptedData.length) {
            chunkSize = encryptedData.length - bytesRead;
        }
        const buffer = encryptedData.slice(bytesRead, bytesRead + chunkSize);
        const pullResult = sodium.crypto_secretstream_xchacha20poly1305_pull(
            pullState,
            buffer,
        );
        decryptedChunks.push(pullResult.message);
        tag = pullResult.tag;
        bytesRead += chunkSize;
    }
    return mergeUint8Arrays(decryptedChunks);
};

/**
 * Prepare to decrypt the result of {@link initChunkEncryption} and
 * {@link encryptStreamChunk}.
 *
 * @param decryptionHeader The header (as a base64 string) that was produced
 * during encryption by {@link initChunkEncryption}.
 *
 * @param key The encryption key.
 *
 * @returns The pull state, which should be treated as opaque libsodium specific
 * state that should be passed along to each subsequent call to
 * {@link decryptStreamChunk}, and the size of each (decrypted) chunk that will
 * be produced by subsequent calls to {@link decryptStreamChunk}.
 */
export const initChunkDecryption = async (
    decryptionHeader: string,
    key: BytesOrB64,
): Promise<InitChunkDecryptionResult> => {
    await sodium.ready;
    const pullState = sodium.crypto_secretstream_xchacha20poly1305_init_pull(
        await fromB64(decryptionHeader),
        await bytes(key),
    );
    const decryptionChunkSize =
        streamEncryptionChunkSize +
        sodium.crypto_secretstream_xchacha20poly1305_ABYTES;
    return { pullState, decryptionChunkSize };
};

/**
 * Decrypt an individual chunk of the data encrypted using
 * {@link initChunkEncryption} and {@link encryptStreamChunk}.
 *
 * This is meant to be used in tandem with {@link initChunkDecryption}. During
 * each invocation, it should be passed the encrypted chunk, and the
 * {@link pullState} returned by {@link initChunkDecryption}. It will then
 * return the corresponding decrypted chunk's bytes.
 */
export const decryptStreamChunk = async (
    data: Uint8Array,
    pullState: SodiumStateAddress,
): Promise<Uint8Array<ArrayBuffer>> => {
    await sodium.ready;
    const pullResult = sodium.crypto_secretstream_xchacha20poly1305_pull(
        pullState,
        data,
    );
    return ensureArrayBufferBacked(pullResult.message);
};

/**
 * Initialize and return new state that can be used to hash the chunks of data
 * in a streaming manner.
 *
 * [Note: Chunked hashing]
 *
 * 1. Obtain a hash state using {@link chunkHashInit}.
 *
 * 2. Pass the hash state and the data chunk to {@link chunkHashUpdate}.
 *
 * 3. Finalize the hash state and obtain the hash using {@link chunkHashFinal}.
 *
 * @returns An opaque object representing the hash state. This can be passed
 * (along with the data to hash) to {@link chunkHashUpdate}, and the final hash
 * obtained using {@link chunkHashFinal}.
 */
export const chunkHashInit = async (): Promise<SodiumStateAddress> => {
    await sodium.ready;
    return sodium.crypto_generichash_init(
        null,
        sodium.crypto_generichash_BYTES_MAX,
    );
};

/**
 * Update the hash state to incorporate the contents of the provided data chunk.
 *
 * See: [Note: Chunked hashing]
 *
 * @param hashState A hash state obtained using {@link chunkHashInit}.
 *
 * @param chunk The data (bytes) to hash.
 */
export const chunkHashUpdate = async (
    hashState: SodiumStateAddress,
    chunk: Uint8Array,
) => {
    await sodium.ready;
    sodium.crypto_generichash_update(hashState, chunk);
};

/**
 * Finalize a hash state and return the hash it represents (as a base64 string).
 *
 * See: [Note: Chunked hashing]
 *
 * @param hashState A hash state obtained using {@link chunkHashInit} and fed
 * chunks using {@link chunkHashUpdate}.
 *
 * @returns The hash of all the chunks (as a base64 string).
 */
export const chunkHashFinal = async (hashState: SodiumStateAddress) => {
    await sodium.ready;
    const hash = sodium.crypto_generichash_final(
        hashState,
        sodium.crypto_generichash_BYTES_MAX,
    );
    return toB64(hash);
};

/**
 * Generate a new public/private keypair for use with public-key encryption
 * functions, and return their base64 string representations.
 *
 * These keys are suitable for being used with the {@link boxSeal} and
 * {@link boxSealOpen} functions.
 */
export const generateKeyPair = async () => {
    await sodium.ready;
    const keyPair = sodium.crypto_box_keypair();
    return {
        publicKey: await toB64(keyPair.publicKey),
        privateKey: await toB64(keyPair.privateKey),
    };
};

/**
 * Public key encryption.
 *
 * Encrypt the given {@link data} using the given {@link publicKey}.
 *
 * This function performs asymmetric (public-key) encryption. To decrypt the
 * result, use {@link boxSealOpen}.
 *
 * @param data The input data to encrypt, represented as a base64 string.
 *
 * @param publicKey The public key to use for encryption (as a base64 string).
 *
 * @returns The encrypted data (as a base64 string).
 */
export const boxSeal = async (data: string, publicKey: string) => {
    await sodium.ready;
    return toB64(
        sodium.crypto_box_seal(await fromB64(data), await fromB64(publicKey)),
    );
};

/**
 * Decrypt the result of {@link boxSeal}.
 *
 * All parameters are base64 string representations of the underlying data. The
 * result is the bytes obtained by decryption.
 */
export const boxSealOpenBytes = async (
    encryptedData: string,
    { publicKey, privateKey }: KeyPair,
): Promise<Uint8Array<ArrayBuffer>> => {
    await sodium.ready;
    return ensureArrayBufferBacked(
        sodium.crypto_box_seal_open(
            await fromB64(encryptedData),
            await fromB64(publicKey),
            await fromB64(privateKey),
        ),
    );
};

/**
 * A variant of {@link boxSealOpenBytes} that returns the result as a base64
 * string.
 */
export const boxSealOpen = async (encryptedData: string, keyPair: KeyPair) =>
    toB64(await boxSealOpenBytes(encryptedData, keyPair));

/**
 * Generate a new randomly generated 128-bit salt suitable for use with the key
 * derivation functions ({@link deriveKey} and its variants).
 *
 * @returns The base64 representation of a randomly generated 128-bit salt.
 */
export const generateDeriveKeySalt = async () => {
    await sodium.ready;
    return await toB64(sodium.randombytes_buf(sodium.crypto_pwhash_SALTBYTES));
};

/**
 * Derive a key by hashing the given {@link passphrase} using Argon 2id.
 *
 * While the underlying primitive is a password hash (e.g for its storage), this
 * function is also meant for key derivation using a low-entropy input by
 * deriving a longer hash from the user's human chosen passphrase.
 *
 * The returned key can be used with the various *Box encryption routines.
 *
 * @param passphrase The password / passphrase to hash (normal UTF-8 string).
 *
 * @param salt Base64 string representing the salt to use when hashing.
 *
 * @param opsLimit Operation limit. The maximum amount of computations to
 * perform.
 *
 * @param memLimit Memory limit. The maximum amount of RAM to use.
 *
 * @returns The base64 representation of a 256-bit key suitable for being used
 * with libsodium's secretbox APIs.
 */
export const deriveKey = async (
    passphrase: string,
    salt: string,
    opsLimit: number,
    memLimit: number,
) => {
    await sodium.ready;
    return await toB64(
        sodium.crypto_pwhash(
            sodium.crypto_secretbox_KEYBYTES,
            sodium.from_string(passphrase),
            await fromB64(salt),
            opsLimit,
            memLimit,
            sodium.crypto_pwhash_ALG_ARGON2ID13,
        ),
    );
};

/**
 * A variant of {@link deriveKey} with (dynamic) parameters for deriving
 * sensitive keys (like the user's master key KEK (key encryption key).
 *
 * This function defers to {@link deriveKey} after choosing the most secure ops
 * and mem limits that the current device can handle. For details about these
 * limits, see https://libsodium.gitbook.io/doc/password_hashing/default_phf.
 *
 * @returns Both the derived key, and the ops and mem limits that were chosen
 * during the derivation (this information will be needed the user's other
 * clients to derive the same result).
 */
export const deriveSensitiveKey = async (
    passphrase: string,
): Promise<DerivedKey> => {
    await sodium.ready;

    const salt = await generateDeriveKeySalt();

    const desiredStrength =
        sodium.crypto_pwhash_MEMLIMIT_SENSITIVE *
        sodium.crypto_pwhash_OPSLIMIT_SENSITIVE;
    // When the sensitive memLimit (1 GB) is used, on low spec devices the OS
    // often kills the app with OOM. Note that could happen at a later stage
    // too, so checking the current device's capabilities will not help. For
    // example, the user may create an account on a powerful desktop device, but
    // then try to log in later on their weaker mobile device, and will need to
    // reset their password.
    //
    // To avoid this, we start with the moderate memLimit (256 MB), but scale up
    // the opsLimit correspondingly (16). This ensures that the product of these
    // two variables (the area under the graph that determines the amount of
    // work) stays the same.
    let memLimit = sodium.crypto_pwhash_MEMLIMIT_MODERATE; // = 256 MB
    const factor = Math.floor(
        sodium.crypto_pwhash_MEMLIMIT_SENSITIVE /
            sodium.crypto_pwhash_MEMLIMIT_MODERATE,
    ); // = 4
    let opsLimit = sodium.crypto_pwhash_OPSLIMIT_SENSITIVE * factor; // = 16
    if (memLimit * opsLimit != desiredStrength) {
        throw new Error(`Invalid mem and ops limits: ${memLimit}, ${opsLimit}`);
    }

    // Keep the adaptive floor aligned with the server-side minimum accepted
    // account KDF memory limit (128 MiB), not libsodium's absolute minimum.
    const minMemLimit = 128 * 1024 * 1024;
    while (memLimit >= minMemLimit) {
        try {
            const key = await deriveKey(passphrase, salt, opsLimit, memLimit);
            return { key, salt, opsLimit, memLimit };
        } catch {
            opsLimit *= 2;
            memLimit /= 2;
        }
    }
    throw new Error(deriveKeyInsufficientMemoryErrorMessage);
};

/**
 * A variant of {@link deriveSensitiveKey} for deriving an alternative key with
 * parameters suitable for interactive use.
 */
export const deriveInteractiveKey = async (
    passphrase: string,
): Promise<DerivedKey> => {
    const salt = await generateDeriveKeySalt();
    const opsLimit = sodium.crypto_pwhash_OPSLIMIT_INTERACTIVE;
    const memLimit = sodium.crypto_pwhash_MEMLIMIT_INTERACTIVE;

    const key = await deriveKey(passphrase, salt, opsLimit, memLimit);
    return { key, salt, opsLimit, memLimit };
};

/**
 * A variant of {@link deriveSensitiveKey} for deriving an alternative key with
 * parameters suitable for moderate-cost password gates.
 */
export const deriveModerateKey = async (
    passphrase: string,
): Promise<DerivedKey> => {
    const salt = await generateDeriveKeySalt();
    const opsLimit = sodium.crypto_pwhash_OPSLIMIT_MODERATE;
    const memLimit = sodium.crypto_pwhash_MEMLIMIT_MODERATE;

    const key = await deriveKey(passphrase, salt, opsLimit, memLimit);
    return { key, salt, opsLimit, memLimit };
};

/**
 * Derive a {@link subKeyID}-th subkey of length {@link subKeyLength} bytes by
 * applying a KDF (Key Derivation Function) for the given {@link key} and the
 * {@link context}.
 *
 * Multiple secret subkeys can be (deterministically) derived from a single
 * high-entropy key. Knowledge of the derived key does not impact the security
 * of the key from which it was derived, or of its potential sibling subkeys.
 *
 * See: https://doc.libsodium.org/key_derivation
 *
 * @param key The key whose subkey we are deriving. In the context of
 * key derivation, this is usually referred to as the "master key", but we
 * deemphasize that nomenclature to avoid confusion with the user's master key.
 *
 * @param subKeyLength The length of the required subkey.
 *
 * @param subKeyID An identifier of the subkey.
 *
 * @param context A short but otherwise arbitrary string (non-secret) used to
 * separate domains in which the subkeys are going to be used.
 *
 * @returns The bytes of the subkey.
 *
 * Note that returning bytes is a bit unusual, usually we'd return the base64
 * string from functions. However, this particular function is used in only one
 * place in our code, and so we adapt the interface for its convenience.
 */
export const deriveSubKeyBytes = async (
    key: BytesOrB64,
    subKeyLength: number,
    subKeyID: number,
    context: string,
): Promise<Uint8Array<ArrayBuffer>> => {
    await sodium.ready;
    return ensureArrayBufferBacked(
        sodium.crypto_kdf_derive_from_key(
            subKeyLength,
            subKeyID,
            context,
            await bytes(key),
        ),
    );
};
