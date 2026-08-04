import type { CastPayload } from "./pair";

export interface CastData {
    collectionID: string;
    collectionKey: string;
    castToken: string;
}

export const clearCastData = () => {
    for (const key of ["collectionID", "collectionKey", "castToken"])
        localStorage.removeItem(key);
};

export const storeCastData = (payload: CastPayload | undefined) => {
    if (!payload || typeof payload != "object")
        throw new Error("Unexpected cast data");

    for (const [key, value] of Object.entries(payload)) {
        if (typeof value == "string" || typeof value == "number") {
            localStorage.setItem(key, value.toString());
        } else {
            localStorage.removeItem(key);
        }
    }
};

export const readCastData = (): CastData | undefined => {
    const collectionID = localStorage.getItem("collectionID");
    const collectionKey = localStorage.getItem("collectionKey");
    const castToken = localStorage.getItem("castToken");

    return collectionID && collectionKey && castToken
        ? { collectionID, collectionKey, castToken }
        : undefined;
};
