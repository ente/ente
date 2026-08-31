import type { WrappedRootContactKey } from "./pkg/ente_photos_wasm";

interface OpenSessionInput {
    baseUrl: string;
    authToken: string;
    masterKeyB64: string;
    clientPackage?: string;
    clientVersion?: string;
}

const wasm = () => import("./pkg/ente_photos_wasm");

export type Session = import("./pkg/ente_photos_wasm").Session;

export const openSession = async ({
    baseUrl,
    authToken,
    masterKeyB64,
    clientPackage,
    clientVersion,
}: OpenSessionInput): Promise<Session> =>
    (await wasm()).openSession(
        baseUrl,
        authToken,
        masterKeyB64,
        clientPackage,
        clientVersion,
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
