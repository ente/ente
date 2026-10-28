import type { PublicAlbumsCredentials } from "ente-base/http";

export interface EnteCredentials extends PublicAlbumsCredentials {
    downloadOrigin: string;
}

export interface EnteFileDescriptor {
    enteFileId: number;
    fileKey: string;
    mediaKind: "image" | "live-photo";
    thumbnailDecryptionHeader: string;
    fileDecryptionHeader: string;
    fileName: string;
    dateTaken: number;
    width: number;
    height: number;
    fileSize?: number;
}
