import type { PublicAlbumsCredentials } from "ente-base/http";

let publicAlbumsCredentials: PublicAlbumsCredentials | undefined;

export const getPublicAlbumsCredentials = () => publicAlbumsCredentials;

export const setPublicAlbumsCredentials = (
    credentials: PublicAlbumsCredentials | undefined,
) => {
    publicAlbumsCredentials = credentials;
};

export const requirePublicAlbumsCredentials = (
    credentials?: PublicAlbumsCredentials,
): PublicAlbumsCredentials => {
    const resolvedCredentials = credentials ?? publicAlbumsCredentials;
    if (!resolvedCredentials) {
        throw new Error("Missing public album credentials");
    }
    return resolvedCredentials;
};
