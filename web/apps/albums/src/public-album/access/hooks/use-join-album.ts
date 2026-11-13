import { joinPublicAlbumViaRedirect } from "@/public-album/access/services/join-public-album-redirect";
import type { PublicAlbumsCredentials } from "ente-base/http";
import type { Collection } from "ente-media/collection";
import type { RefObject } from "react";

export interface UseJoinAlbumProps {
    publicCollection?: Collection;
    accessToken?: string;
    collectionKey?: string;
    credentials?: RefObject<PublicAlbumsCredentials | undefined>;
}

export interface UseJoinAlbumReturn {
    handleJoinAlbum: () => void;
}

export const useJoinAlbum = ({
    publicCollection,
    accessToken,
    collectionKey,
    credentials,
}: UseJoinAlbumProps): UseJoinAlbumReturn => {
    const handleJoinAlbum = () =>
        joinPublicAlbumViaRedirect({
            publicCollection,
            accessToken,
            collectionKey,
            credentials,
        });

    return { handleJoinAlbum };
};
