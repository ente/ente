import { ComlinkWorker } from "ente-base/worker/comlink-worker";
import { inWorker } from "../env";
// Main-thread callers must use this module.
// Call libsodium directly only from a worker.
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

let _comlinkWorker: ComlinkWorker<typeof CryptoWorker> | undefined;

const sharedWorker = () =>
    (_comlinkWorker ??= createComlinkCryptoWorker()).remote;

export const createComlinkCryptoWorker = () =>
    new ComlinkWorker<typeof CryptoWorker>(
        "crypto",
        new Worker(new URL("worker.ts", import.meta.url)),
    );

export const toB64 = (bytes: Uint8Array): Promise<string> =>
    inWorker()
        ? libsodium.toB64(bytes)
        : sharedWorker().then((w) => w.toB64(bytes));

export const fromB64 = (b64String: string): Promise<Uint8Array> =>
    inWorker()
        ? libsodium.fromB64(b64String)
        : sharedWorker().then((w) => w.fromB64(b64String));

export const toB64URLSafe = (bytes: Uint8Array): Promise<string> =>
    inWorker()
        ? libsodium.toB64URLSafe(bytes)
        : sharedWorker().then((w) => w.toB64URLSafe(bytes));

export const toB64URLSafeNoPadding = (bytes: Uint8Array): Promise<string> =>
    inWorker()
        ? libsodium.toB64URLSafeNoPadding(bytes)
        : sharedWorker().then((w) => w.toB64URLSafeNoPadding(bytes));

export const fromB64URLSafeNoPadding = (
    b64String: string,
): Promise<Uint8Array> =>
    inWorker()
        ? libsodium.fromB64URLSafeNoPadding(b64String)
        : sharedWorker().then((w) => w.fromB64URLSafeNoPadding(b64String));

export const toHex = (b64String: string): Promise<string> =>
    inWorker()
        ? libsodium.toHex(b64String)
        : sharedWorker().then((w) => w.toHex(b64String));

export const fromHex = (hexString: string): Promise<string> =>
    inWorker()
        ? libsodium.fromHex(hexString)
        : sharedWorker().then((w) => w.fromHex(hexString));

export const generateKey = (): Promise<string> =>
    inWorker()
        ? libsodium.generateKey()
        : sharedWorker().then((w) => w.generateKey());

export const generateBlobOrStreamKey = (): Promise<string> =>
    inWorker()
        ? libsodium.generateBlobOrStreamKey()
        : sharedWorker().then((w) => w.generateBlobOrStreamKey());

export const encryptBox = (
    data: BytesOrB64,
    key: BytesOrB64,
): Promise<EncryptedBoxB64> =>
    inWorker()
        ? libsodium.encryptBox(data, key)
        : sharedWorker().then((w) => w.encryptBox(data, key));

export const encryptBlob = (
    data: BytesOrB64,
    key: BytesOrB64,
): Promise<EncryptedBlobB64> =>
    inWorker()
        ? libsodium.encryptBlob(data, key)
        : sharedWorker().then((w) => w.encryptBlob(data, key));

export const encryptBlobBytes = (
    data: BytesOrB64,
    key: BytesOrB64,
): Promise<EncryptedBlobBytes> =>
    inWorker()
        ? libsodium.encryptBlobBytes(data, key)
        : sharedWorker().then((w) => w.encryptBlobBytes(data, key));

export const encryptMetadataJSON = (
    jsonValue: unknown,
    key: BytesOrB64,
): Promise<EncryptedBlobB64> =>
    inWorker()
        ? libsodium.encryptMetadataJSON(jsonValue, key)
        : sharedWorker().then((w) => w.encryptMetadataJSON(jsonValue, key));

export const encryptStreamBytes = (
    data: Uint8Array,
    key: BytesOrB64,
): Promise<EncryptedFile> =>
    inWorker()
        ? libsodium.encryptStreamBytes(data, key)
        : sharedWorker().then((w) => w.encryptStreamBytes(data, key));

export const initChunkEncryption = (
    key: BytesOrB64,
): Promise<InitChunkEncryptionResult> =>
    inWorker()
        ? libsodium.initChunkEncryption(key)
        : sharedWorker().then((w) => w.initChunkEncryption(key));

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

export const decryptBox = (
    box: EncryptedBox,
    key: BytesOrB64,
): Promise<string> =>
    inWorker()
        ? libsodium.decryptBox(box, key)
        : sharedWorker().then((w) => w.decryptBox(box, key));

export const decryptBoxBytes = (
    box: EncryptedBox,
    key: BytesOrB64,
): Promise<Uint8Array<ArrayBuffer>> =>
    inWorker()
        ? libsodium.decryptBoxBytes(box, key)
        : sharedWorker().then((w) => w.decryptBoxBytes(box, key));

export const decryptBlob = (
    blob: EncryptedBlob,
    key: BytesOrB64,
): Promise<string> =>
    inWorker()
        ? libsodium.decryptBlob(blob, key)
        : sharedWorker().then((w) => w.decryptBlob(blob, key));

export const decryptBlobBytes = (
    blob: EncryptedBlob,
    key: BytesOrB64,
): Promise<Uint8Array<ArrayBuffer>> =>
    inWorker()
        ? libsodium.decryptBlobBytes(blob, key)
        : sharedWorker().then((w) => w.decryptBlobBytes(blob, key));

export const decryptStreamBytes = (
    file: EncryptedFile,
    key: BytesOrB64,
): Promise<Uint8Array<ArrayBuffer>> =>
    inWorker()
        ? libsodium.decryptStreamBytes(file, key)
        : sharedWorker().then((w) => w.decryptStreamBytes(file, key));

export const initChunkDecryption = (
    header: string,
    key: BytesOrB64,
): Promise<InitChunkDecryptionResult> =>
    inWorker()
        ? libsodium.initChunkDecryption(header, key)
        : sharedWorker().then((w) => w.initChunkDecryption(header, key));

export const decryptStreamChunk = (
    data: Uint8Array,
    state: SodiumStateAddress,
): Promise<Uint8Array<ArrayBuffer>> =>
    inWorker()
        ? libsodium.decryptStreamChunk(data, state)
        : sharedWorker().then((w) => w.decryptStreamChunk(data, state));

export const decryptMetadataJSON = (
    blob: EncryptedBlob,
    key: BytesOrB64,
): Promise<unknown> =>
    inWorker()
        ? libsodium.decryptMetadataJSON(blob, key)
        : sharedWorker().then((w) => w.decryptMetadataJSON(blob, key));

export const generateKeyPair = (): Promise<KeyPair> =>
    inWorker()
        ? libsodium.generateKeyPair()
        : sharedWorker().then((w) => w.generateKeyPair());

export const boxSeal = (data: string, publicKey: string): Promise<string> =>
    inWorker()
        ? libsodium.boxSeal(data, publicKey)
        : sharedWorker().then((w) => w.boxSeal(data, publicKey));

export const boxSealOpen = (
    encryptedData: string,
    keyPair: KeyPair,
): Promise<string> =>
    inWorker()
        ? libsodium.boxSealOpen(encryptedData, keyPair)
        : sharedWorker().then((w) => w.boxSealOpen(encryptedData, keyPair));

export const boxSealOpenBytes = (
    encryptedData: string,
    keyPair: KeyPair,
): Promise<Uint8Array> =>
    inWorker()
        ? libsodium.boxSealOpenBytes(encryptedData, keyPair)
        : sharedWorker().then((w) =>
              w.boxSealOpenBytes(encryptedData, keyPair),
          );

export const generateDeriveKeySalt = (): Promise<string> =>
    inWorker()
        ? libsodium.generateDeriveKeySalt()
        : sharedWorker().then((w) => w.generateDeriveKeySalt());

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

export const deriveInteractiveKey = (
    passphrase: string,
): Promise<DerivedKey> =>
    inWorker()
        ? libsodium.deriveInteractiveKey(passphrase)
        : sharedWorker().then((w) => w.deriveInteractiveKey(passphrase));

export const deriveModerateKey = (passphrase: string): Promise<DerivedKey> =>
    inWorker()
        ? libsodium.deriveModerateKey(passphrase)
        : sharedWorker().then((w) => w.deriveModerateKey(passphrase));

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
