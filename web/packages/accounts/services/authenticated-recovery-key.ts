interface EncryptedBox {
    encryptedData: string;
    nonce: string;
}

export const createAuthenticatedRecoveryKeyOps = <
    Session extends { recoveryKeyMnemonic: () => string },
>({
    ensureSession,
    generateKey,
    encryptBox,
}: {
    ensureSession: () => Promise<Session>;
    generateKey: () => Promise<string>;
    encryptBox: (
        session: Session,
        data: string,
    ) => EncryptedBox | Promise<EncryptedBox>;
}) => {
    const recoveryKeyMnemonic = async () =>
        (await ensureSession()).recoveryKeyMnemonic();

    const encryptWithRecoveryKey = async (data: string) => {
        const session = await ensureSession();
        return encryptBox(session, data);
    };

    const generatePasskeyRecovery = async () => {
        const session = await ensureSession();
        const secret = await generateKey();
        return { secret, ...(await encryptBox(session, secret)) };
    };

    return {
        encryptWithRecoveryKey,
        generatePasskeyRecovery,
        recoveryKeyMnemonic,
    };
};
