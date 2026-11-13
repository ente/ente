interface FileLinkMeta {
    encryptedFileKey?: string;
    encryptedFileKeyNonce?: string;
    kdfNonce?: string;
    kdfMemLimit?: number;
    kdfOpsLimit?: number;
}

export interface FileLinkInfo {
    file?: {
        id?: number;
        ownerID?: number;
        collectionID?: number;
        encryptedKey?: string;
        keyDecryptionNonce?: string;
        file?: { decryptionHeader?: string; size?: number };
        thumbnail?: { decryptionHeader?: string; size?: number };
        metadata?: {
            encryptedData?: string;
            decryptionHeader?: string;
            size?: number;
        };
        info?: { fileSize?: number; thumbSize?: number };
        isDeleted?: boolean;
        updationTime?: number;
        pubMagicMetadata?: {
            version?: number;
            count?: number;
            data?: string;
            header?: string;
        };
        // Older responses used these flat fields instead of the nested
        // metadata object above.
        encryptedMetadata?: string;
        metadataDecryptionHeader?: string;
        fileSize?: number;
        uploadedTime?: number;
    };
    ownerName?: string;
    link?: FileLinkMeta;
}

export interface LockerInfoData {
    content?: string;
    location?: string;
    notes?: string;
    username?: string;
    password?: string;
    contactDetails?: string;
    size?: number;
}

export interface LockerInfo {
    type?: string;
    data?: LockerInfoData;
}

export interface FileMetadata {
    fileName?: string;
    title?: string;
    name?: string;
    fileSize?: number;
    size?: number;
    uploadedTime?: number;
    createdAt?: number;
    modificationTime?: number;
}

export interface DecryptedFileInfo {
    id: number;
    fileName: string;
    fileSize: number;
    uploadedTime: number;
    ownerName?: string;
    fileDecryptionHeader?: string;
    fileNonce?: string;
    fileKey?: string;
    lockerType?: string;
    lockerInfoData?: LockerInfoData;
}

export type LinkKeyMaterial =
    | { type: "direct"; fileKey: string }
    | { type: "secret"; passphrase: string };
