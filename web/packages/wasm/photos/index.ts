import { readAndFree } from "ente-utils/wasm";
import type {
    OpenSessionInput,
    Session,
    WrappedRootContactKey,
} from "./pkg/ente_photos_wasm";

const wasm = () => import("./pkg/ente_photos_wasm");

export type { OpenSessionInput, Session } from "./pkg/ente_photos_wasm";

export const openSession = async (input: OpenSessionInput): Promise<Session> =>
    (await wasm()).openSession(input);

export const encryptBoxWithRecoveryKey = (session: Session, dataB64: string) =>
    readAndFree(session.encryptWithRecoveryKey(dataB64), (box) => ({
        encryptedData: box.encryptedData,
        nonce: box.nonce,
    }));

export const generateKey = async () => (await wasm()).cryptoGenerateKey();

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
