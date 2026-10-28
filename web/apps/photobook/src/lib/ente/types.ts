// Types for the Ente public album integration. Mirrors the shapes in
// ente-media (web/packages/media/) but kept permissive — we accept unknown
// fields and only validate what we use.

export type EnteMediaKind = "image" | "live-photo";

export interface EnteCredentials {
    apiOrigin: string;
    albumsOrigin: string;
    accessToken: string;
    collectionKey: string;
    accessTokenJWT?: string;
}

export interface EntePasswordParams {
    nonce: string;
    opsLimit: number;
    memLimit: number;
}

export interface EntePublicCollectionInfo {
    referralCode?: string;
    publicURL: {
        passwordEnabled: boolean;
        password?: EntePasswordParams;
        enableDownload: boolean;
        validTill: number;
        deviceLimit: number;
    };
    encryptedName?: string;
    nameDecryptionNonce?: string;
    plainName?: string;
    updationTime: number;
}

export interface EnteRemoteFile {
    id: number;
    encryptedKey: string;
    keyDecryptionNonce: string;
    file: { decryptionHeader: string };
    thumbnail: { decryptionHeader: string };
    metadata: { encryptedData: string; decryptionHeader: string };
    pubMagicMetadata?: { encryptedData?: string; decryptionHeader: string };
    info?: { fileSize?: number; thumbSize?: number };
    updationTime: number;
    isDeleted?: boolean;
}

export interface EnteFileMetadata {
    fileType: number; // 0=image, 1=video, 2=live-photo
    title?: string;
    creationTime: number; // microseconds since epoch
    modificationTime: number; // microseconds since epoch
    hash?: string;
}

export interface EntePublicMagicMetadata {
    editedTime?: number;
    editedName?: string;
    w?: number;
    h?: number;
    dateTime?: string;
}

export interface EnteFileDescriptor {
    enteFileId: number;
    fileKey: string;
    mediaKind: EnteMediaKind;
    thumbnailDecryptionHeader: string;
    fileDecryptionHeader: string;
    fileName: string;
    dateTaken: number;
    width: number;
    height: number;
    fileSize?: number;
}
