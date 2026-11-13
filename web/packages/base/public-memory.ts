import { publicRequestHeaders } from "ente-base/http";

export interface PublicMemoryCredentials {
    accessToken: string;
}

export const authenticatedPublicMemoryRequestHeaders = ({
    accessToken,
}: PublicMemoryCredentials) => ({
    "X-Auth-Access-Token": accessToken,
    ...publicRequestHeaders(),
});
