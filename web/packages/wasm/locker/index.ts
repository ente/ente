import { wrap } from "comlink";
import { workerReady } from "ente-utils/worker";
import type { FileLinkWorker } from "./file-link.worker";
import type {
    EncryptedBlob,
    EncryptedBox,
    OpenSessionInput,
    Session,
    WrappedRootContactKey,
} from "./pkg/ente_locker_wasm";

export type { OpenSessionInput, Session } from "./pkg/ente_locker_wasm";

const wasm = () => import("./pkg/ente_locker_wasm");

export const openSession = async (input: OpenSessionInput): Promise<Session> =>
    (await wasm()).openSession(input);

export const recoveryKeyMnemonic = async (session: Session) =>
    (await wasm()).authRecoveryKeyMnemonic(session);

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
    (await wasm()).cryptoEncryptBox(dataB64, keyB64);

export const encryptBoxBytes = async (data: Uint8Array, keyB64: string) =>
    (await wasm()).cryptoEncryptBoxBytes(data, keyB64);

export const decryptBox = async (
    box: EncryptedBox,
    keyB64: string,
): Promise<string> =>
    (await wasm()).cryptoDecryptBox(box.encryptedData, box.nonce, keyB64);

export const decryptBoxBytes = async (
    box: EncryptedBox,
    keyB64: string,
): Promise<Uint8Array> =>
    (await wasm()).cryptoDecryptBoxBytes(box.encryptedData, box.nonce, keyB64);

export const encryptBlob = async (data: Uint8Array, keyB64: string) =>
    (await wasm()).cryptoEncryptBlob(data, keyB64);

export const decryptMetadataJSON = async (
    blob: EncryptedBlob,
    keyB64: string,
): Promise<unknown> => {
    const plaintext = (await wasm()).cryptoDecryptBlobLegacy(
        blob.encryptedData,
        blob.decryptionHeader,
        keyB64,
    );
    return JSON.parse(new TextDecoder().decode(plaintext));
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
) => (await wasm()).cryptoEncryptStreamWithKey(dataB64, keyB64);
