import type { CastPayload } from "./pair";

export interface CastData {
    /** The ID of the callection we are casting. */
    collectionID: string;
    /** A key to decrypt the collection we are casting. */
    collectionKey: string;
    /** A credential to use for fetching media files for this cast session. */
    castToken: string;
}

export const clearCastData = () => {
    for (const key of ["collectionID", "collectionKey", "castToken"])
        localStorage.removeItem(key);
};

/**
 * Save the data received after pairing with a sender into local storage.
 *
 * We will read in back when we start the slideshow.
 */
export const storeCastData = (payload: CastPayload | undefined) => {
    if (!payload || typeof payload != "object")
        throw new Error("Unexpected cast data");

    // Iterate through all the keys of the payload object and save them to
    // localStorage. We don't validate here, we'll validate when we read these
    // values back in `readCastData`.
    for (const [key, value] of Object.entries(payload)) {
        if (typeof value == "string" || typeof value == "number") {
            localStorage.setItem(key, value.toString());
        } else {
            localStorage.removeItem(key);
        }
    }
};

/**
 * Read back the cast data we got after pairing.
 *
 * Sibling of {@link storeCastData}. It returns undefined if the expected data
 * is not present in localStorage.
 */
export const readCastData = (): CastData | undefined => {
    const collectionID = localStorage.getItem("collectionID");
    const collectionKey = localStorage.getItem("collectionKey");
    const castToken = localStorage.getItem("castToken");

    return collectionID && collectionKey && castToken
        ? { collectionID, collectionKey, castToken }
        : undefined;
};
