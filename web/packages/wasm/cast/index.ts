const wasm = () => import("./pkg/ente_cast_wasm");

export type CastReceiver = import("./pkg/ente_cast_wasm").CastReceiver;

export interface CastPayload {
    castToken: string;
    collectionID: number;
    collectionKey: string;
}

export interface PreparedCastPayload {
    castToken: string;
    encryptedPayload: string;
}

export const createCastReceiver = async (): Promise<CastReceiver> =>
    new (await wasm()).CastReceiver();

export const openCastPayload = (
    receiver: CastReceiver,
    encryptedPayload: string,
): CastPayload =>
    plainValue(receiver.openPayload(encryptedPayload), (payload) => ({
        castToken: payload.castToken,
        collectionID: Number(payload.collectionID),
        collectionKey: payload.collectionKey,
    }));

export const prepareCastPayload = async (
    publicKey: string,
    pqPublicKey: string | undefined,
    collectionID: number,
    collectionKey: string,
): Promise<PreparedCastPayload> =>
    plainValue(
        (await wasm()).preparePayload(
            publicKey,
            pqPublicKey,
            BigInt(collectionID),
            collectionKey,
        ),
        (payload) => ({
            castToken: payload.castToken,
            encryptedPayload: payload.encryptedPayload,
        }),
    );

const plainValue = <T extends { free: () => void }, U>(
    value: T,
    read: (value: T) => U,
) => {
    try {
        return read(value);
    } finally {
        value.free();
    }
};
