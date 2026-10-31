import type {
    EncryptedBox,
    ExecuteDuplicateRemovalInput,
    FindDuplicatesInput,
    LocationIndex,
    OpenSessionInput,
    Session,
    WrappedRootContactKey,
} from "./pkg/ente_photos_wasm";

export type {
    AccountDeletionSummary,
    LocationCityGroup,
    OpenSessionInput,
    Session,
} from "./pkg/ente_photos_wasm";

const wasm = () => import("./pkg/ente_photos_wasm");

export const findDuplicates = async (input: FindDuplicatesInput) =>
    (await wasm()).photosFindDuplicates(input);

export const executeDuplicateRemoval = async (
    session: Session,
    input: ExecuteDuplicateRemovalInput,
    onProgress: (completed: number, total: number) => void,
) => (await wasm()).photosExecuteDuplicateRemoval(session, input, onProgress);

export const createLocationIndex = async (
    cities: Uint8Array,
    urbanCenters: Uint8Array,
): Promise<LocationIndex> =>
    new (await wasm()).LocationIndex(cities, urbanCenters);

export const openSession = async (input: OpenSessionInput): Promise<Session> =>
    (await wasm()).openSession(input);

export const getAccountDeletionSummary = async (session: Session) =>
    (await wasm()).getAccountDeletionSummary(session);

export const getAccountDeleteChallenge = async (session: Session) =>
    (await wasm()).getAccountDeleteChallenge(session);

export const deleteAccount = async (
    session: Session,
    encryptedChallenge: string,
    reason: string,
    feedback?: string,
) =>
    (await wasm()).deleteAccount(session, encryptedChallenge, reason, feedback);

export const recoveryKeyMnemonic = async (session: Session) =>
    (await wasm()).authRecoveryKeyMnemonic(session);

export const generateKey = async () => (await wasm()).cryptoGenerateKey();

export const encryptBox = async (dataB64: string, keyB64: string) =>
    (await wasm()).cryptoEncryptBox(dataB64, keyB64);

export const decryptBox = async (box: EncryptedBox, keyB64: string) =>
    (await wasm()).cryptoDecryptBox(box.encryptedData, box.nonce, keyB64);

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

export const prepareCastPayload = async (
    publicKey: string,
    pqPublicKey: string | undefined,
    collectionID: number,
    collectionKey: string,
) =>
    (await wasm()).castPreparePayload(
        publicKey,
        pqPublicKey,
        BigInt(collectionID),
        collectionKey,
    );
