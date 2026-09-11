import { savedKeyAttributes } from "ente-accounts/services/accounts-db";
import {
    decryptBox,
    encryptBox,
    recoveryKeyFromMnemonicOrHex,
} from "ente-accounts/services/crypto";
import { ensureMasterKeyFromSession } from "ente-accounts/services/prelogin-session";
import { recoveryKeyToMnemonic } from "ente-prelogin-wasm";

// For legacy compatibility, the hex representation of the recovery key is
// accepted in addition to the 24 word BIP-39 mnemonic.
export const recoveryKeyFromMnemonic = (recoveryKeyMnemonicOrHex: string) =>
    recoveryKeyFromMnemonicOrHex(recoveryKeyMnemonicOrHex);

const preloginRecoveryKey = async () => {
    const masterKey = await ensureMasterKeyFromSession();

    const keyAttributes = savedKeyAttributes();
    const { recoveryKeyEncryptedWithMasterKey, recoveryKeyDecryptionNonce } =
        keyAttributes ?? {};

    if (!recoveryKeyEncryptedWithMasterKey || !recoveryKeyDecryptionNonce)
        throw new Error("Missing recovery key");

    return decryptBox(
        {
            encryptedData: recoveryKeyEncryptedWithMasterKey,
            nonce: recoveryKeyDecryptionNonce,
        },
        masterKey,
    );
};

export const getPreloginRecoveryKeyMnemonic = async () =>
    recoveryKeyToMnemonic(await preloginRecoveryKey());

export const encryptWithPreloginRecoveryKey = async (data: string) =>
    encryptBox(data, await preloginRecoveryKey());
