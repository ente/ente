import { getKVS, removeKV, setKV } from "./kv";

export const ensureAuthToken = async () => {
    const token = await savedAuthToken();
    if (!token) throw new Error("Not logged in");
    return token;
};

export const savedAuthToken = () => getKVS("token");

export const saveAuthToken = (token: string) => setKV("token", token);

export const removeAuthToken = () => removeKV("token");
