import {
    publicKey,
    verificationID,
    type Session,
} from "ente-legacy-wasm/authenticated";

export {
    addContact as legacyAddContact,
    changePassword as legacyChangePassword,
} from "ente-legacy-wasm/authenticated";

export const legacyVerificationID = async (session: Session, email: string) => {
    const key = await publicKey(session, email);
    return key ? verificationID(key) : undefined;
};
