import { mergeUint8Arrays } from "ente-utils/array";
import { ensureArrayBufferBacked } from "ente-utils/bytes";
import sodium from "libsodium-wrappers-sumo";
import {
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

export const toB64 = async (input: Uint8Array) => {
    await sodium.ready;
    return sodium.to_base64(input, sodium.base64_variants.ORIGINAL);
};

export const fromB64 = async (
    input: string,
): Promise<Uint8Array<ArrayBuffer>> => {
    await sodium.ready;
    return ensureArrayBufferBacked(
        sodium.from_base64(input, sodium.base64_variants.ORIGINAL),
    );
};

export const toB64URLSafe = async (input: Uint8Array) => {
    await sodium.ready;
    return sodium.to_base64(input, sodium.base64_variants.URLSAFE);
};

export const toB64URLSafeNoPadding = async (input: Uint8Array) => {
    await sodium.ready;
    return sodium.to_base64(input, sodium.base64_variants.URLSAFE_NO_PADDING);
};

export const fromB64URLSafeNoPadding = async (
    input: string,
): Promise<Uint8Array<ArrayBuffer>> => {
    await sodium.ready;
    return ensureArrayBufferBacked(
        sodium.from_base64(input, sodium.base64_variants.URLSAFE_NO_PADDING),
    );
};

export const toHex = async (input: string) => {
    await sodium.ready;
    return sodium.to_hex(await fromB64(input));
};

export const fromHex = async (input: string): Promise<string> => {
    await sodium.ready;
    return await toB64(sodium.from_hex(input));
};

const bytes = async (bob: BytesOrB64) =>
    typeof bob == "string" ? fromB64(bob) : bob;

export const generateKey = async () => {
    await sodium.ready;
    return toB64(sodium.crypto_secretbox_keygen());
};

export const generateBlobOrStreamKey = async () => {
    await sodium.ready;
    return toB64(sodium.crypto_secretstream_xchacha20poly1305_keygen());
};

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

export const encryptMetadataJSON = (
    jsonValue: unknown,
    key: BytesOrB64,
): Promise<EncryptedBlobB64> =>
    encryptBlob(new TextEncoder().encode(JSON.stringify(jsonValue)), key);

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
        // Equality marks the last full-size chunk as final.
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

export const initChunkEncryption = async (
    key: BytesOrB64,
): Promise<InitChunkEncryptionResult> => {
    await sodium.ready;
    const keyBytes = await bytes(key);
    const { state, header } =
        sodium.crypto_secretstream_xchacha20poly1305_init_push(keyBytes);
    return { decryptionHeader: await toB64(header), pushState: state };
};

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

export const decryptBox = (
    box: EncryptedBox,
    key: BytesOrB64,
): Promise<string> => decryptBoxBytes(box, key).then(toB64);

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

export const decryptBlob = (
    blob: EncryptedBlob,
    key: BytesOrB64,
): Promise<string> => decryptBlobBytes(blob, key).then(toB64);

export const decryptMetadataJSON = async (
    blob: EncryptedBlob,
    key: BytesOrB64,
): Promise<unknown> =>
    JSON.parse(
        new TextDecoder().decode(await decryptBlobBytes(blob, key)),
    ) as unknown;

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
        // Equality is still a complete encrypted chunk.
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

export const chunkHashInit = async (): Promise<SodiumStateAddress> => {
    await sodium.ready;
    return sodium.crypto_generichash_init(
        null,
        sodium.crypto_generichash_BYTES_MAX,
    );
};

export const chunkHashUpdate = async (
    hashState: SodiumStateAddress,
    chunk: Uint8Array,
) => {
    await sodium.ready;
    sodium.crypto_generichash_update(hashState, chunk);
};

export const chunkHashFinal = async (hashState: SodiumStateAddress) => {
    await sodium.ready;
    const hash = sodium.crypto_generichash_final(
        hashState,
        sodium.crypto_generichash_BYTES_MAX,
    );
    return toB64(hash);
};

export const generateKeyPair = async () => {
    await sodium.ready;
    const keyPair = sodium.crypto_box_keypair();
    return {
        publicKey: await toB64(keyPair.publicKey),
        privateKey: await toB64(keyPair.privateKey),
    };
};

export const boxSeal = async (data: string, publicKey: string) => {
    await sodium.ready;
    return toB64(
        sodium.crypto_box_seal(await fromB64(data), await fromB64(publicKey)),
    );
};

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

export const boxSealOpen = async (encryptedData: string, keyPair: KeyPair) =>
    toB64(await boxSealOpenBytes(encryptedData, keyPair));

export const generateDeriveKeySalt = async () => {
    await sodium.ready;
    return await toB64(sodium.randombytes_buf(sodium.crypto_pwhash_SALTBYTES));
};

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

export const deriveInteractiveKey = async (
    passphrase: string,
): Promise<DerivedKey> => {
    const salt = await generateDeriveKeySalt();
    const opsLimit = sodium.crypto_pwhash_OPSLIMIT_INTERACTIVE;
    const memLimit = sodium.crypto_pwhash_MEMLIMIT_INTERACTIVE;

    const key = await deriveKey(passphrase, salt, opsLimit, memLimit);
    return { key, salt, opsLimit, memLimit };
};

export const deriveModerateKey = async (
    passphrase: string,
): Promise<DerivedKey> => {
    const salt = await generateDeriveKeySalt();
    const opsLimit = sodium.crypto_pwhash_OPSLIMIT_MODERATE;
    const memLimit = sodium.crypto_pwhash_MEMLIMIT_MODERATE;

    const key = await deriveKey(passphrase, salt, opsLimit, memLimit);
    return { key, salt, opsLimit, memLimit };
};

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
