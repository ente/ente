import { deriveInteractiveKey, encryptBox } from "./crypto";
import type { KeyAttributes } from "./user";

export const generateInteractiveKeyAttributes = async (
    password: string,
    keyAttributes: KeyAttributes,
    masterKey: string,
): Promise<KeyAttributes> => {
    const {
        key: kek,
        salt: kekSalt,
        opsLimit,
        memLimit,
    } = await deriveInteractiveKey(password);
    const { encryptedData: encryptedKey, nonce: keyDecryptionNonce } =
        await encryptBox(masterKey, kek);
    return {
        ...keyAttributes,
        encryptedKey,
        keyDecryptionNonce,
        kekSalt,
        opsLimit,
        memLimit,
    };
};
