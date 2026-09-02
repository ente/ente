const wasm = () => import("./pkg/ente_ensu_wasm");

export const generateChatKey = async () => (await wasm()).generateChatKey();

export const encryptChatPayload = async (value: string, keyB64: string) => {
    const payload = (await wasm()).encryptChatPayload(value, keyB64);
    try {
        return { encryptedData: payload.encryptedData, header: payload.header };
    } finally {
        payload.free();
    }
};

export const decryptChatPayload = async (
    encryptedDataB64: string,
    headerB64: string,
    keyB64: string,
) => (await wasm()).decryptChatPayload(encryptedDataB64, headerB64, keyB64);

export const encryptChatField = async (value: string, keyB64: string) =>
    (await wasm()).encryptChatField(value, keyB64);

export const decryptChatField = async (value: string, keyB64: string) =>
    (await wasm()).decryptChatField(value, keyB64);

export const encryptChatAttachment = async (
    data: Uint8Array,
    keyB64: string,
    sessionUUID: string,
): Promise<Uint8Array> =>
    (await wasm()).encryptChatAttachment(data, keyB64, sessionUUID);

export const decryptChatAttachment = async (
    data: Uint8Array,
    keyB64: string,
    sessionUUID: string,
): Promise<Uint8Array> =>
    (await wasm()).decryptChatAttachment(data, keyB64, sessionUUID);
