export const JOIN_ALBUM_CONTEXT_KEY = "ente_join_album_context";

export interface JoinAlbumContext {
    accessToken: string;
    // Base64-encoded collection key used by the API.
    collectionKey: string;
    // Unmodified base58 or hex value from the URL.
    collectionKeyHash: string;
    collectionID: number;
    accessTokenJWT?: string;
}

export const getJoinAlbumContext = (): JoinAlbumContext | null => {
    const stored = sessionStorage.getItem(JOIN_ALBUM_CONTEXT_KEY);
    if (!stored) {
        return null;
    }

    try {
        return JSON.parse(stored) as JoinAlbumContext;
    } catch {
        return null;
    }
};

export const clearJoinAlbumContext = () => {
    sessionStorage.removeItem(JOIN_ALBUM_CONTEXT_KEY);
};

export const hasPendingAlbumToJoin = (): boolean => {
    return getJoinAlbumContext() !== null;
};
