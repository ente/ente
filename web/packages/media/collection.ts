import { decryptBoxBytes } from "ente-base/crypto";
import {
    nullishToEmpty,
    nullishToFalse,
    nullToUndefined,
} from "ente-utils/transform";
import { z } from "zod";
import {
    decryptMagicMetadata,
    RemoteMagicMetadata,
    type MagicMetadata,
} from "./magic-metadata";

export interface Collection {
    id: number;
    owner: CollectionUser;
    key: string;
    name: string;
    type: string;
    sharees: CollectionUser[];
    publicURLs: PublicURL[];
    updationTime: number;
    // Private to the owner; never visible to sharees.
    magicMetadata?: MagicMetadata<CollectionPrivateMagicMetadataData>;
    // Visible to everyone with whom the collection is shared.
    pubMagicMetadata?: MagicMetadata<CollectionPublicMagicMetadataData>;
    // Set by and visible to only the individual sharee; the owner and other
    // sharees never see it.
    sharedMagicMetadata?: MagicMetadata<CollectionShareeMagicMetadataData>;
}

export const collectionTypes = [
    "album",
    "folder",
    "favorites",
    "uncategorized",
] as const;

export type CollectionType = (typeof collectionTypes)[number];

interface CollectionTypeAndOwner {
    type: string;
    owner: { id: number };
}

// Files cannot be orphaned. Their last membership moves to Uncategorized.
// The owner check excludes a sharee's Uncategorized collection.
export const findUserUncategorizedCollection = <
    T extends CollectionTypeAndOwner,
>(
    collections: readonly T[],
    userID: number,
) =>
    collections.find(
        (collection) =>
            collection.type == "uncategorized" && collection.owner.id == userID,
    );

export type CollectionParticipantRole =
    | "VIEWER"
    | "COLLABORATOR"
    | "ADMIN"
    | "OWNER"
    | "UNKNOWN";

export type CollectionNewParticipantRole = "VIEWER" | "COLLABORATOR" | "ADMIN";

export interface CollectionUser {
    id: number;
    email?: string;
    role?: string;
}

// Keep remote enums open-ended so newer values survive older clients.
export const RemoteCollectionUser = z.looseObject({
    id: z.number(),
    email: z.string().nullish().transform(nullToUndefined),
    role: z.string().nullish().transform(nullToUndefined),
});

type RemoteCollectionUser = z.infer<typeof RemoteCollectionUser>;

export interface PublicURL {
    // The URL is of the form "https://albums.ente.com/?t=<token>", without a
    // fragment. The decryption key is client side only and never reaches
    // remote; the client appends it as the fragment to form the shareable URL.
    url: string;
    deviceLimit: number;
    // This is an epoch microseconds timestamp; 0 means no expiry.
    validTill: number;
    enableDownload: boolean;
    enableJoin: boolean;
    enableCollect: boolean;
    enableComment: boolean;
    passwordEnabled: boolean;
    nonce?: string;
    opsLimit?: number;
    memLimit?: number;
}

export const RemotePublicURL = z.looseObject({
    url: z.string(),
    deviceLimit: z.number(),
    validTill: z.number(),
    enableDownload: z.boolean().nullish().transform(nullishToFalse),
    enableJoin: z.boolean().nullish().transform(nullishToFalse),
    enableCollect: z.boolean().nullish().transform(nullishToFalse),
    enableComment: z.boolean().nullish().transform(nullishToFalse),
    passwordEnabled: z.boolean().nullish().transform(nullishToFalse),
    nonce: z.string().nullish().transform(nullToUndefined),
    memLimit: z.number().nullish().transform(nullToUndefined),
    opsLimit: z.number().nullish().transform(nullToUndefined),
});

// This uses looseObject so that fields unknown to this client survive the
// round trip through the local database and remain readable by future
// versions of the client.
export const RemoteCollection = z.looseObject({
    id: z.number(),
    owner: RemoteCollectionUser,
    encryptedKey: z.string(),
    keyDecryptionNonce: z.string().nullish().transform(nullToUndefined),
    encryptedName: z.string().nullish().transform(nullToUndefined),
    nameDecryptionNonce: z.string().nullish().transform(nullToUndefined),
    name: z.string().nullish().transform(nullToUndefined),
    type: z.string(),
    sharees: z.array(RemoteCollectionUser).nullish().transform(nullishToEmpty),
    publicURLs: z.array(RemotePublicURL).nullish().transform(nullishToEmpty),
    updationTime: z.number(),
    isDeleted: z.boolean().nullish().transform(nullToUndefined),
    magicMetadata: RemoteMagicMetadata.nullish().transform(nullToUndefined),
    pubMagicMetadata: RemoteMagicMetadata.nullish().transform(nullToUndefined),
    sharedMagicMetadata:
        RemoteMagicMetadata.nullish().transform(nullToUndefined),
});

export type RemoteCollection = z.infer<typeof RemoteCollection>;

export const decryptRemoteCollection = async (
    collection: RemoteCollection,
    collectionKey: string,
): Promise<Collection> => {
    // Destructure every field that gets dropped or transformed; the spread
    // keeps the remaining (possibly unknown) fields intact in the result.
    const {
        owner,
        encryptedKey,
        keyDecryptionNonce,
        encryptedName,
        nameDecryptionNonce,
        sharees,
        // The attributes field is mobile specific and unused by the web clients.
        attributes,
        isDeleted,
        magicMetadata: encryptedMagicMetadata,
        pubMagicMetadata: encryptedPubMagicMetadata,
        sharedMagicMetadata: encryptedSharedMagicMetadata,
        ...rest
    } = collection;

    const name =
        // The `||` is deliberate: remote sets name to blank to indicate
        // absence. Only very old collections, created before names were
        // encrypted, have a plaintext name.
        collection.name ||
        new TextDecoder().decode(
            await decryptBoxBytes(
                { encryptedData: encryptedName!, nonce: nameDecryptionNonce! },
                collectionKey,
            ),
        );

    let magicMetadata: Collection["magicMetadata"];
    if (encryptedMagicMetadata) {
        const genericMM = await decryptMagicMetadata(
            encryptedMagicMetadata,
            collectionKey,
        );
        const data = CollectionPrivateMagicMetadataData.parse(genericMM.data);
        magicMetadata = { ...genericMM, data };
    }

    let pubMagicMetadata: Collection["pubMagicMetadata"];
    if (encryptedPubMagicMetadata) {
        const genericMM = await decryptMagicMetadata(
            encryptedPubMagicMetadata,
            collectionKey,
        );
        const data = CollectionPublicMagicMetadataData.parse(genericMM.data);
        pubMagicMetadata = { ...genericMM, data };
    }

    let sharedMagicMetadata: Collection["sharedMagicMetadata"];
    if (encryptedSharedMagicMetadata) {
        const genericMM = await decryptMagicMetadata(
            encryptedSharedMagicMetadata,
            collectionKey,
        );
        const data = CollectionShareeMagicMetadataData.parse(genericMM.data);
        sharedMagicMetadata = { ...genericMM, data };
    }

    return {
        ...rest,
        key: collectionKey,
        owner: parseRemoteCollectionUser(owner),
        name,
        sharees: sharees.map(parseRemoteCollectionUser),
        magicMetadata,
        pubMagicMetadata,
        sharedMagicMetadata,
    };
};

const parseRemoteCollectionUser = ({
    name,
    ...rest
}: RemoteCollectionUser): CollectionUser => rest;

export const CollectionSubType = {
    default: 0,
    defaultHidden: 1,
    quicklink: 2,
} as const;

export type CollectionSubType =
    (typeof CollectionSubType)[keyof typeof CollectionSubType];

export const CollectionOrder = { default: 0, pinned: 1 } as const;

export type CollectionOrder =
    (typeof CollectionOrder)[keyof typeof CollectionOrder];

export interface CollectionPrivateMagicMetadataData {
    subType?: number;
    visibility?: number;
    order?: number;
}

// Metadata Zod schemas use looseObject because unknown fields must be
// retained verbatim: metadata edits get pushed back to remote, and dropping
// fields written by other clients would destroy them.
export const CollectionPrivateMagicMetadataData = z.looseObject({
    subType: z.number().nullish().transform(nullToUndefined),
    visibility: z.number().nullish().transform(nullToUndefined),
    order: z.number().nullish().transform(nullToUndefined),
});

export interface CollectionPublicMagicMetadataData {
    asc?: boolean;
    coverID?: number;
    layout?: string;
    caption?: string;
}

export const maxAlbumDescriptionLength = 200;

export const CollectionPublicMagicMetadataData = z.looseObject({
    asc: z.boolean().nullish().transform(nullToUndefined),
    coverID: z.number().nullish().transform(nullToUndefined),
    layout: z.string().nullish().transform(nullToUndefined),
    caption: z.string().nullish().transform(nullToUndefined),
});

export interface CollectionShareeMagicMetadataData {
    visibility?: number;
    order?: number;
}

export const CollectionShareeMagicMetadataData = z.looseObject({
    visibility: z.number().nullish().transform(nullToUndefined),
    order: z.number().nullish().transform(nullToUndefined),
});
