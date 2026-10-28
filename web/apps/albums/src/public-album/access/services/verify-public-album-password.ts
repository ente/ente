import type { PublicURL } from "ente-media/collection";
import { verifyPublicCollectionPassword } from "ente-media/public-albums";

export const verifyPublicAlbumPassword = async (
    publicURL: PublicURL,
    password: string,
    accessToken: string,
) => verifyPublicCollectionPassword({ accessToken }, publicURL, password);
