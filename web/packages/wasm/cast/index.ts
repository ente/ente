import type { CastReceiver } from "./pkg/ente_cast_wasm";

export type { CastReceiver } from "./pkg/ente_cast_wasm";

const wasm = () => import("./pkg/ente_cast_wasm");

export const createCastReceiver = async (): Promise<CastReceiver> =>
    new (await wasm()).CastReceiver();

export const openCastPayload = (
    receiver: CastReceiver,
    encryptedPayload: string,
) => receiver.openPayload(encryptedPayload);
