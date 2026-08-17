import { savedKeyAttributes } from "ente-accounts/services/accounts-db";
import {
    decryptBox,
    encryptBox,
    generateKey,
    recoveryKeyFromMnemonicOrHex,
    recoveryKeyToMnemonicRust,
} from "ente-accounts/services/crypto";
import { ensureMasterKeyFromSession } from "ente-accounts/services/session-storage";
import { saveKeyAttributes } from "./accounts-db";
import { putUserRecoveryKeyAttributes, type KeyAttributes } from "./user";

// For legacy compatibility, the hex representation of the recovery key is
// accepted in addition to the 24 word BIP-39 mnemonic.
export const recoveryKeyFromMnemonic = (recoveryKeyMnemonicOrHex: string) =>
    recoveryKeyFromMnemonicOrHex(recoveryKeyMnemonicOrHex);

export const recoveryKeyToMnemonic = async (recoveryKey: string) =>
    recoveryKeyToMnemonicRust(recoveryKey);

export const getUserRecoveryKey = async () => {
    const masterKey = await ensureMasterKeyFromSession();

    const keyAttributes = savedKeyAttributes()!;
    const { recoveryKeyEncryptedWithMasterKey, recoveryKeyDecryptionNonce } =
        keyAttributes;

    if (recoveryKeyEncryptedWithMasterKey && recoveryKeyDecryptionNonce) {
        return decryptBox(
            {
                encryptedData: recoveryKeyEncryptedWithMasterKey,
                nonce: recoveryKeyDecryptionNonce,
            },
            masterKey,
        );
    } else {
        return createNewRecoveryKey(masterKey, keyAttributes);
    }
};

// Very old accounts did not get a recovery key at sign up; for them one is
// generated lazily when it is first needed.
const createNewRecoveryKey = async (
    masterKey: string,
    existingKeyAttributes: KeyAttributes,
) => {
    const recoveryKey = await generateKey();
    const encryptedMasterKey = await encryptBox(masterKey, recoveryKey);
    const encryptedRecoveryKey = await encryptBox(recoveryKey, masterKey);

    const recoveryKeyAttributes = {
        masterKeyEncryptedWithRecoveryKey: encryptedMasterKey.encryptedData,
        masterKeyDecryptionNonce: encryptedMasterKey.nonce,
        recoveryKeyEncryptedWithMasterKey: encryptedRecoveryKey.encryptedData,
        recoveryKeyDecryptionNonce: encryptedRecoveryKey.nonce,
    };

    await putUserRecoveryKeyAttributes(recoveryKeyAttributes);

    saveKeyAttributes({ ...existingKeyAttributes, ...recoveryKeyAttributes });

    return recoveryKey;
};
