// Adapted from `web/packages/base/token.ts`.
import { getKVS, kvKeys, removeKV, setKV } from "./storage";

export const ensureAuthToken = async () => {
    const token = await savedAuthToken();
    if (!token) throw new Error("Not logged in");
    return token;
};

export const savedAuthToken = () => getKVS(kvKeys.token);

export const saveAuthToken = (token: string) => setKV(kvKeys.token, token);

export const removeAuthToken = () => removeKV(kvKeys.token);
