import type {
    KeyAttributes,
    LegacyContactState,
    Session,
} from "./pkg/ente_legacy_wasm";

export type {
    LegacyContactRecord,
    LegacyContactState,
    LegacyInfo,
    LegacyRecoverySession,
    LegacyRecoveryStatus,
    LegacyUser,
    Session,
} from "./pkg/ente_legacy_wasm";

interface OpenSessionInput {
    baseUrl: string;
    authToken: string;
    masterKeyB64: string;
    clientPackage?: string;
    clientVersion?: string;
}

const wasm = () => import("./pkg/ente_legacy_wasm");

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

export const getInfo = async (session: Session) =>
    (await wasm()).legacyGetInfo(session);

export const publicKey = async (session: Session, email: string) =>
    (await wasm()).legacyPublicKey(session, email);

export const verificationID = async (publicKeyB64: string) =>
    (await wasm()).legacyVerificationID(publicKeyB64);

export const addContact = async (
    session: Session,
    email: string,
    currentUserKeyAttributes: KeyAttributes,
    recoveryNoticeInDays?: number,
) =>
    (await wasm()).legacyAddContact(
        session,
        email,
        currentUserKeyAttributes,
        recoveryNoticeInDays,
    );

export const updateContact = async (
    session: Session,
    userID: number,
    emergencyContactID: number,
    state: LegacyContactState,
) =>
    (await wasm()).legacyUpdateContact(
        session,
        BigInt(userID),
        BigInt(emergencyContactID),
        state,
    );

export const updateRecoveryNotice = async (
    session: Session,
    emergencyContactID: number,
    recoveryNoticeInDays: number,
) =>
    (await wasm()).legacyUpdateRecoveryNotice(
        session,
        BigInt(emergencyContactID),
        recoveryNoticeInDays,
    );

export const startRecovery = async (
    session: Session,
    userID: number,
    emergencyContactID: number,
) =>
    (await wasm()).legacyStartRecovery(
        session,
        BigInt(userID),
        BigInt(emergencyContactID),
    );

export const stopRecovery = async (
    session: Session,
    recoveryID: string,
    userID: number,
    emergencyContactID: number,
) =>
    (await wasm()).legacyStopRecovery(
        session,
        recoveryID,
        BigInt(userID),
        BigInt(emergencyContactID),
    );

export const rejectRecovery = async (
    session: Session,
    recoveryID: string,
    userID: number,
    emergencyContactID: number,
) =>
    (await wasm()).legacyRejectRecovery(
        session,
        recoveryID,
        BigInt(userID),
        BigInt(emergencyContactID),
    );

export const changePassword = async (
    session: Session,
    recoveryID: string,
    currentUserKeyAttributes: KeyAttributes,
    newPassword: string,
) =>
    (await wasm()).legacyChangePassword(
        session,
        recoveryID,
        currentUserKeyAttributes,
        newPassword,
    );
