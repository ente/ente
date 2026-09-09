import { wrap } from "comlink";
import { readAndFree } from "ente-utils/wasm";
import { workerReady } from "ente-utils/worker";
import type { FileLinkWorker } from "./file-link.worker";
import type {
    OpenSessionInput,
    Session,
    WrappedRootContactKey,
} from "./pkg/ente_locker_wasm";

const wasm = () => import("./pkg/ente_locker_wasm");

export type { OpenSessionInput, Session } from "./pkg/ente_locker_wasm";

export const openSession = async (input: OpenSessionInput): Promise<Session> =>
    (await wasm()).openSession(input);

export const openCollectionKey = async (
    session: Session,
    ownerID: number,
    encryptedKey: string,
    keyDecryptionNonce?: string,
) =>
    (await wasm()).collectionsOpenKey(
        session,
        BigInt(ownerID),
        encryptedKey,
        keyDecryptionNonce,
    );

export const contactsGetDiff = async (
    session: Session,
    wrappedRootContactKey: WrappedRootContactKey | undefined,
    sinceTime: number,
    limit: number,
) =>
    (await wasm()).contactsGetDiff(
        session,
        wrappedRootContactKey?.encryptedKey,
        wrappedRootContactKey?.header,
        BigInt(sinceTime),
        limit,
    );

export const contactsGetProfilePicture = async (
    session: Session,
    wrappedRootContactKey: WrappedRootContactKey | undefined,
    contactID: string,
) =>
    (await wasm()).contactsGetProfilePicture(
        session,
        wrappedRootContactKey?.encryptedKey,
        wrappedRootContactKey?.header,
        contactID,
    );

type BytesOrB64 = Uint8Array | string;

interface EncryptedBlob {
    encryptedData: BytesOrB64;
    decryptionHeader: BytesOrB64;
}

interface EncryptedBox {
    encryptedData: BytesOrB64;
    nonce: BytesOrB64;
}

export const prepareFileLink = async (session: Session, fileKeyB64: string) => {
    const worker = new Worker(new URL("file-link.worker.ts", import.meta.url));
    const RemoteWorker = wrap<typeof FileLinkWorker>(worker);
    const remote = await workerReady(worker, new RemoteWorker());
    try {
        const payload = await remote.prepareFileLinkPayload(fileKeyB64);
        const encryptedShareKey = (await wasm()).lockerSealFileLinkSecret(
            session,
            payload.fragment,
        );
        return {
            secret: payload.fragment,
            metadata: {
                encryptedFileKey: payload.encryptedFileKey,
                encryptedFileKeyNonce: payload.encryptedFileKeyNonce,
                kdfNonce: payload.kdfNonce,
                kdfMemLimit: payload.kdfMemLimit,
                kdfOpsLimit: payload.kdfOpsLimit,
                encryptedShareKey,
            },
        };
    } finally {
        worker.terminate();
    }
};

export const openFileLinkSecret = async (
    session: Session,
    encryptedShareKey: string,
) => (await wasm()).lockerOpenFileLinkSecret(session, encryptedShareKey);

export const generateKey = async () => (await wasm()).cryptoGenerateKey();

export const encryptBox = async (dataB64: string, keyB64: string) =>
    readAndFree((await wasm()).cryptoEncryptBox(dataB64, keyB64), (box) => ({
        encryptedData: box.encryptedData,
        nonce: box.nonce,
    }));

export const decryptBox = async (
    box: EncryptedBox,
    key: Uint8Array | string,
): Promise<string> =>
    (await wasm()).cryptoDecryptBox(
        toB64String(box.encryptedData),
        toB64String(box.nonce),
        toB64String(key),
    );

export const decryptBoxBytes = async (
    box: EncryptedBox,
    key: Uint8Array | string,
): Promise<Uint8Array<ArrayBuffer>> =>
    fromB64String(await decryptBox(box, key));

export const encryptBlob = async (dataB64: string, keyB64: string) =>
    readAndFree((await wasm()).cryptoEncryptBlob(dataB64, keyB64), (blob) => ({
        encryptedData: blob.encryptedData,
        decryptionHeader: blob.decryptionHeader,
    }));

export const decryptMetadataJSON = async (
    blob: EncryptedBlob,
    key: Uint8Array | string,
): Promise<unknown> => {
    const wasmModule = await wasm();
    const encryptedData = toB64String(blob.encryptedData);
    const decryptionHeader = toB64String(blob.decryptionHeader);
    const keyB64 = toB64String(key);
    let plaintextB64: string;
    try {
        plaintextB64 = wasmModule.cryptoDecryptBlob(
            encryptedData,
            decryptionHeader,
            keyB64,
        );
    } catch (error) {
        if (!(error instanceof Error && error.name == "stream_truncated")) {
            throw error;
        }
        plaintextB64 = wasmModule.cryptoDecryptBlobLegacy(
            encryptedData,
            decryptionHeader,
            keyB64,
        );
    }
    return JSON.parse(new TextDecoder().decode(fromB64String(plaintextB64)));
};

export const boxSeal = async (
    dataB64: string,
    publicKeyB64: string,
): Promise<string> => (await wasm()).cryptoBoxSeal(dataB64, publicKeyB64);

export const md5Base64 = async (data: Uint8Array) =>
    (await wasm()).cryptoMd5Base64(data);

export const createStreamEncryptor = async () =>
    new (await wasm()).CryptoStreamEncryptor();

export const createStreamDecryptor = async (
    decryptionHeaderB64: string,
    keyB64: string,
) => new (await wasm()).CryptoStreamDecryptor(decryptionHeaderB64, keyB64);

export const encryptFileStreamWithKey = async (
    dataB64: string,
    keyB64: string,
) =>
    readAndFree(
        (await wasm()).cryptoEncryptStreamWithKey(dataB64, keyB64),
        (file) => ({
            encryptedData: file.encryptedData,
            decryptionHeader: file.decryptionHeader,
            md5Hash: file.md5Hash,
        }),
    );

export const stringToB64 = (value: string): string =>
    toB64String(new TextEncoder().encode(value));

export const b64ToBytes = (value: string): Uint8Array<ArrayBuffer> =>
    fromB64String(value);

const toB64String = (value: Uint8Array | string): string => {
    if (typeof value == "string") return value;
    let binary = "";
    for (const byte of value) binary += String.fromCharCode(byte);
    return btoa(binary);
};

const fromB64String = (value: string): Uint8Array<ArrayBuffer> => {
    const binary = atob(value);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
};
