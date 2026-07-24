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

/**
 * A collection, as used and persisted locally by the client.
 *
 * A collection is, well, a collection of files. It is roughly equivalent to an
 * "album" (which is also the term we use in the UI), but there can also be
 * special type of collections like "favorites" which have special behaviour.
 *
 * A collection contains zero or more files ({@link EnteFile}).
 *
 * A collection can be owned by the user (in whose context this code is
 * running), or might be a collection that is shared with them.
 */
export interface Collection {
    /**
     * The collection's globally unique ID.
     *
     * The collection's ID is a integer assigned by remote as the identifier for
     * an {@link Collection} when it is created. It is globally unique across
     * all collections on an Ente instance (i.e., it is not scoped to a user).
     */
    id: number;
    /**
     * Information about the user who owns the collection.
     *
     * Each collection is owned by exactly one user. The owner may optionally
     * choose to share it with additional users, granting them varying level of
     * privileges.
     *
     * Within the {@link CollectionUser} instance of the {@link owner} field:
     *
     * - {@link email} will be set only if this is a shared collection that does
     *   not belong to the current user.
     * - {@link role} will be blank.
     */
    owner: CollectionUser;
    /**
     * The "collection key" (base64 encoded).
     *
     * The collection key is used to encrypt and decrypt that files that are
     * associated with the collection. See: [Note: Collection file].
     */
    key: string;
    /**
     * The name of the collection.
     */
    name: string;
    /**
     * The type of the collection.
     *
     * Expected to be one of {@link CollectionType}.
     */
    type: string;
    /**
     * The other Ente users with whom the collection has been shared with.
     *
     * Within the {@link CollectionUser} instances of the {@link sharee} field:
     *
     * - {@link email} will be set.
     * - {@link role} is expected to be one of "VIEWER" or "COLLABORATOR".
     */
    sharees: CollectionUser[];
    /**
     * Public links that can be used to access and update the collection.
     */
    publicURLs: PublicURL[];
    /**
     * The last time the collection was updated (epoch microseconds).
     *
     * The collection is considered updated both
     *
     * - When the files associated with it modified (added, removed); and
     * - When the collection's own fields are modified.
     */
    updationTime: number;
    /**
     * Private mutable metadata associated with the collection that is only
     * visible to the owner of the collection.
     *
     * See: [Note: Metadatum]
     */
    magicMetadata?: MagicMetadata<CollectionPrivateMagicMetadataData>;
    /**
     * Public mutable metadata associated with the collection that is visible to
     * all users with whom the collection has been shared.
     *
     * See: [Note: Metadatum]
     */
    pubMagicMetadata?: MagicMetadata<CollectionPublicMagicMetadataData>;
    /**
     * Private mutable metadata associated with the collection that is only
     * visible to the current user if they're not the owner of the collection.
     *
     * Sometimes also referred to as "shareeMagicMetadata".
     *
     * This is metadata associated with each "share", and is only visible to
     * (and editable by) the user with which the collection has been shared, not
     * the owner. Each user with whom the collection has been shared gets their
     * own private copy. This allows each user to keep their own metadata
     * associated with a shared album (e.g. archive status).
     *
     * See: [Note: Metadatum]
     */
    sharedMagicMetadata?: MagicMetadata<CollectionShareeMagicMetadataData>;
}

/**
 * The known set of values for the {@link type} field of a {@link Collection}.
 *
 * This is the list of values, see {@link CollectionType} for the corresponding
 * TypeScript type.
 */
export const collectionTypes = [
    "album",
    "folder",
    "favorites",
    "uncategorized",
] as const;

/**
 * The type of a collection.
 *
 * - "album" - A regular "Ente Album" that the user sees in their library.
 *
 * - "folder" - An Ente Album that is also associated with an OS album on the
 *   user's mobile device.
 *
 *   A collection of type "folder" is created by the mobile app if there is an
 *   associated on-device album for the new Ente album being created.
 *
 *   This separation between "album" and "folder" allows different mobile
 *   clients to push to the same Folder ("Camera", "Screenshots"), not allowing
 *   for duplicate folders with the same name, while still allowing users to
 *   create different albums with the same name.
 *
 *   The web/desktop app does not create collections of type "folder", and
 *   otherwise treats them as aliases for "album".
 *
 * - "favorites" - A special collection consisting of the items that the user
 *   has marked as their favorites.
 *
 *   The user can have at most one collection of type "favorites" (enforced at
 *   remote). This collection is created on demand by the client where the user
 *   first marks an item as a favorite. The user can choose to share their
 *   "favorites" with other users, so it is possible for there to be multiple
 *   collections of type "favorites" present in our local database, however only
 *   one of those will belong to the logged in user (cf `owner.id`).
 *
 * - "uncategorized" - A special collection consisting of items that do not
 *   belong to any other collection.
 *
 *   In the remote schema, each item ({@link EnteFile}) is always associated
 *   with a collection. The same item may belong to multiple collections (See:
 *   [Note: Collection file]), but it must belong to at least one collection.
 *
 *   In some scenarios, e.g. when deleting the last collection to which a file
 *   belongs, the file would thus get orphaned and violate the schema
 *   invariants. So in such cases, the client which is performing the
 *   corresponding operation moves the file to the user's special
 *   "uncategorized" collection, creating it if needed.
 *
 *   Similar to "favorites", the user can own only one "uncategorized"
 *   collection. Shared collections of this type can also be present locally,
 *   so callers must include the owner when resolving the user's collection.
 */
export type CollectionType = (typeof collectionTypes)[number];

interface CollectionTypeAndOwner {
    type: string;
    owner: { id: number };
}

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

/**
 * The privilege level of a participant associated with a collection.
 *
 * - "VIEWER" - Has read-only access to files in the collection.
 *
 * - "COLLABORATOR" - Can additionally add files from the collection, and remove
 *   files that they added from the collection (i.e., files they "own").
 *
 * - "ADMIN" - Can manage participants (invite/remove) similar to the owner, but
 *   cannot delete the collection or remove the owner.
 *
 * - "OWNER" - The owner of the collection. Can remove any file, including those
 *   added by other users, from the collection.
 *
 * It is guaranteed that a there will be exactly one participant of type OWNER,
 * and their user ID will be the same as the collection `owner.id`.
 */
export type CollectionParticipantRole =
    | "VIEWER"
    | "COLLABORATOR"
    | "ADMIN"
    | "OWNER"
    | "UNKNOWN";

/**
 * A subset of {@link CollectionParticipantRole} that are applicable when
 * sharing a collection with another Ente user.
 */
export type CollectionNewParticipantRole = "VIEWER" | "COLLABORATOR" | "ADMIN";

/**
 * Information about the user associated with a collection, either as an owner,
 * or as someone with whom the collection has been shared with.
 */
export interface CollectionUser {
    /**
     * The ID of the underlying {@link User} that this {@link CollectionUser}
     * stands for.
     */
    id: number;
    /**
     * The email of the user.
     *
     * - The email is present for the {@link owner} only for shared collections
     *   that do not belong to the current user.
     * - The email is present for all {@link sharees}.
     * - Remote uses a blank string to indicate absent values.
     */
    email?: string;
    /**
     * The association / privilege level of the user with the collection.
     *
     * Expected to be one of {@link CollectionParticipantRole}.
     *
     * - The role is not present (blank string) for the {@link owner}.
     * - The role is present, and one of "VIEWER" and "COLLABORATOR" for the
     *   {@link sharees}.
     * - Remote uses a blank string to indicate absent values.
     */
    role?: string;
}

/**
 * Zod schema for {@link CollectionUser}.
 *
 * [Note: Enums in remote objects]
 *
 * In some cases remote returns a value which is part of a known set. The
 * underlying type might be an integer or a string.
 *
 * While Zod allows us to validate enum types during a parse, we refrain from
 * doing this as this would cause existing clients to break if remote were to in
 * the future add new enum cases.
 *
 * This is especially pertinent for objects which we might persist locally,
 * since the client code which persists the object might not know about a
 * particular enum case but a future client which reads the saved value might.
 *
 * So we keep the underlying data type (string or number) as it is instead of
 * converting / validating to an enum or discarding unknown values.
 *
 * As an example consider the {@link role} item in {@link RemoteCollectionUser}.
 * There is a known set of values ({@link CollectionParticipantRole}) this can
 * be, but in the Zod schema we keep the data type as a string.
 */
export const RemoteCollectionUser = z.looseObject({
    id: z.number(),
    email: z.string().nullish().transform(nullToUndefined),
    role: z.string().nullish().transform(nullToUndefined),
});

type RemoteCollectionUser = z.infer<typeof RemoteCollectionUser>;

/**
 * A public link for a shared collection.
 *
 * This structure contains a (partial^) URL that can be used to access the
 * shared collection, along with other attributes of the link.
 *
 * ^ The URL is partial because it doesn't have the URL fragment, which is
 *   client side only as it contains the decryption key
 */
export interface PublicURL {
    /**
     * A URL that can be used access the shared collection.
     *
     * This will be of the form "https://<public-albums-app>/<token>", e.g.,
     * "https://albums.ente.com/xxxxxx".
     *
     * In particular, this URL does not contain the URL fragment (the part after
     * the "#"). URL fragments are client side only, and not sent to remote.
     * They contain the decryption key.
     *
     * The client can use this field to form the fully usable URL, e.g.
     * "https://albums.ente.com/xxxxxx#yyy...yyy", and provide it to the user
     * for sharing.
     */
    url: string;
    /**
     * The number of unique devices which can access the collection using the
     * public URL.
     *
     * Set to 0 to indicate no device limit.
     */
    deviceLimit: number;
    /**
     * The epoch microseconds until which the link is valid.
     *
     * Set to 0 to indicate no expiry.
     */
    validTill: number;
    /**
     * `true` if downloads are enabled from this link.
     *
     * When creating a new link this is `true` by default, and can optionally be
     * disabled in the public link settings.
     */
    enableDownload: boolean;
    enableJoin: boolean;
    /**
     * `true` if people can use the public link to upload new files to the
     * shared collection.
     */
    enableCollect: boolean;
    /**
     * `true` if comments are enabled on this public link.
     */
    enableComment: boolean;
    /**
     * `true` if the link is password protected.
     *
     * When this is `true`, {@link nonce}, {@link memLimit} and {@link opsLimit}
     * will also be set.
     */
    passwordEnabled: boolean;
    /**
     * The nonce to use when hashing the password.
     *
     * Only present when {@link passwordEnabled} is `true`.
     */
    nonce?: string;
    /**
     * The ops limit to use when hashing the password.
     *
     * Only present when {@link passwordEnabled} is `true`.
     */
    opsLimit?: number;
    /**
     * The mem limit to use when hashing the password.
     *
     * Only present when {@link passwordEnabled} is `true`.
     */
    memLimit?: number;
}

/**
 * Zod schema for the {@link PublicURL} we use in our interactions with remote.
 *
 * We also use the same schema when persisting the collection locally.
 */
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

/**
 * Zod schema for {@link Collection}.
 *
 * [Note: Use looseObject when parsing JSON that will get persisted]
 *
 * While not always necessary, for a few cases (files and collections being the
 * most prominent and important) we try to retain any unknown fields in the JSON
 * we get from remote, so that future versions of the client with support for
 * fields unbeknownst to the current one can read and use them.
 *
 * In such cases, the nested objects should also (recursively) use the
 * looseObject schema. But not always - in some cases where the structures we
 * use are well established, e.g. {@link RemoteMagicMetadata} - we use the
 * default Zod behaviour of discarding unknown fields.
 *
 * > Note that even in the case of {@link RemoteMagicMetadata}, we still apply
 * > looseObject to the payload itself.
 * >
 * > See: [Note: Use looseObject for metadata Zod schemas]
 *
 * Unlike metadata, where we do strictly want to retain unknown or unacted on
 * fields, in the more general case we are okay with being a bit loose with
 * looseObject, and even intentionally dropping fields that we know we're not
 * going to use on the current client. Such looseness is okay because even if we
 * need to use them in the future, we can always refetch the objects again
 * (while in the case of metadata, we need to also push our changes to remote,
 * so it is functionally important for us to retain the source verbatim).
 */
export const RemoteCollection = z.looseObject({
    id: z.number(),
    owner: RemoteCollectionUser,
    encryptedKey: z.string(),
    /**
     * The nonce to use when decrypting the {@link encryptedKey} when the album
     * is owned by the user.
     *
     * Not set for shared albums (the decryption for uses the keypair instead).
     *
     * Remote might set this to blank to indicate absence.
     */
    keyDecryptionNonce: z.string().nullish().transform(nullToUndefined),
    /**
     * Expected to be present (along with {@link nameDecryptionNonce}), but it
     * is still optional since it might not be present if {@link name} is present.
     */
    encryptedName: z.string().nullish().transform(nullToUndefined),
    nameDecryptionNonce: z.string().nullish().transform(nullToUndefined),
    /**
     * Not used anymore, but still might be present for very old collections.
     *
     * Before public launch, collection names were stored unencrypted. For
     * backward compatibility, client should use {@link name} if present,
     * otherwise obtain it by decrypting it from {@link encryptedName} and
     * {@link nameDecryptionNonce}.
     */
    name: z.string().nullish().transform(nullToUndefined),
    /**
     * Expected to be one of {@link CollectionType}
     */
    type: z.string(),
    sharees: z.array(RemoteCollectionUser).nullish().transform(nullishToEmpty),
    publicURLs: z.array(RemotePublicURL).nullish().transform(nullishToEmpty),
    updationTime: z.number(),
    /**
     * Tombstone marker.
     *
     * This is set to `true` in the collection fetch response to indicate
     * collections which have been deleted on remote and should thus be pruned
     * by the client locally.
     */
    isDeleted: z.boolean().nullish().transform(nullToUndefined),
    magicMetadata: RemoteMagicMetadata.nullish().transform(nullToUndefined),
    pubMagicMetadata: RemoteMagicMetadata.nullish().transform(nullToUndefined),
    sharedMagicMetadata:
        RemoteMagicMetadata.nullish().transform(nullToUndefined),
});

export type RemoteCollection = z.infer<typeof RemoteCollection>;

/**
 * Decrypt a remote collection using the provided {@link collectionKey}.
 *
 * @param collection The remote collection to decrypt.
 *
 * @param collectionKey The base64 encoded key to use for decrypting the various
 * encrypted fields in {@link collection}.
 *
 * @returns A decrypted collection.
 */
export const decryptRemoteCollection = async (
    collection: RemoteCollection,
    collectionKey: string,
): Promise<Collection> => {
    // RemoteCollection is a looseObject, and we want to retain that semantic
    // for the parsed Collection. Mention all fields that we want to explicitly
    // drop or transform, passthrough the rest unchanged in the return value.
    //
    // See: [Note: Use looseObject when parsing JSON that will get persisted].
    const {
        owner,
        encryptedKey,
        keyDecryptionNonce,
        encryptedName,
        nameDecryptionNonce,
        sharees,
        attributes,
        isDeleted,
        magicMetadata: encryptedMagicMetadata,
        pubMagicMetadata: encryptedPubMagicMetadata,
        sharedMagicMetadata: encryptedSharedMagicMetadata,
        ...rest
    } = collection;

    // We've already used them to derive the `collectionKey`.
    ignore([encryptedKey, keyDecryptionNonce]);
    // Mobile specific attribute not currently used by us.
    ignore(attributes);
    // The deleted flag is used during collection fetch, but not used by us
    // beyond this point.
    ignore(isDeleted);

    const name =
        // `||` is used because remote sets name to blank to indicate absence.
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
        publicURLs: rest.publicURLs,
        magicMetadata,
        pubMagicMetadata,
        sharedMagicMetadata,
    };
};

/**
 * A no-op function to pretend that we're using some values. This is handy when
 * we want to destructure some fields so that they don't get forwarded, but
 * otherwise don't need to use them.
 */
export const ignore = (xs: unknown) => typeof xs;

/**
 * A convenience function to discard the unused name field from the collection
 * user objects that we receive from remote.
 */
const parseRemoteCollectionUser = ({
    name,
    ...rest
}: RemoteCollectionUser): CollectionUser => {
    ignore(name);
    return rest;
};

/**
 * Additional context stored as part of the collection's magic metadata to
 * augment the {@link type} associated with a {@link Collection}.
 */
export const CollectionSubType = {
    /**
     * The default / normal value. No special semantics.
     */
    default: 0,
    /**
     * The user's default hidden collection, which contains the individually
     * hidden files.
     */
    defaultHidden: 1,
    /**
     * A collection created for sharing selected files.
     */
    quicklink: 2,
} as const;

export type CollectionSubType =
    (typeof CollectionSubType)[keyof typeof CollectionSubType];

/**
 * Ordering of the collection - Whether it is pinned or not.
 */
export const CollectionOrder = {
    /**
     * The default / normal value. No special semantics, behaves "unpinned" and
     * will retain its natural sort position.
     */
    default: 0,
    /**
     * The collection is "pinned" by moving to the beginning of the sort order.
     *
     * Multiple collections can be pinned, in which case they'll be sorted
     * amongst themselves under the otherwise applicable sort order.
     *
     *     -- [pinned collections] -- [other collections] --
     */
    pinned: 1,
} as const;

export type CollectionOrder =
    (typeof CollectionOrder)[keyof typeof CollectionOrder];

/**
 * Mutable private metadata associated with a {@link Collection}.
 *
 * - Unlike {@link CollectionPublicMagicMetadataData} this is only available to
 *   the owner of the file.
 *
 * See: [Note: Private magic metadata is called magic metadata on remote]
 */
export interface CollectionPrivateMagicMetadataData {
    /**
     * The subtype of the collection type (if applicable).
     *
     * Expected to be one of {@link CollectionSubType}.
     */
    subType?: number;
    /**
     * The (owner specific) visibility of the collection.
     *
     * The file's visibility is user specific attribute, and thus we keep it in
     * the private magic metadata. This allows the file's owner to share a file
     * and independently edit its visibility without revealing their visibility
     * preference to the other people with whom they have shared the file.
     *
     * Expected to be one of {@link ItemVisibility}.
     *
     * See: [Note: Enums in remote objects] for why we keep it as a number
     * instead of the expected enum.
     */
    visibility?: number;
    /**
     * An overrride to the sort ordering used for the collection.
     *
     * Expected to be one of {@link CollectionOrder}.
     */
    order?: number;
}

/**
 * Zod schema for {@link CollectionPrivateMagicMetadataData}.
 *
 * See: [Note: Use looseObject for metadata Zod schemas]
 */
export const CollectionPrivateMagicMetadataData = z.looseObject({
    subType: z.number().nullish().transform(nullToUndefined),
    visibility: z.number().nullish().transform(nullToUndefined),
    order: z.number().nullish().transform(nullToUndefined),
});

/**
 * Mutable public metadata associated with a {@link Collection}.
 *
 * - Unlike {@link CollectionPrivateMagicMetadataData}, this is available to all
 *   people with whom the collection has been shared.
 *
 * For more details, see [Note: Metadatum].
 */
export interface CollectionPublicMagicMetadataData {
    /**
     * The ordering of the files within the collection.
     *
     * The default is desc ("Newest first").
     *
     * If true, then the files within the collection are sorted in ascending
     * order of their time ("Oldest first").
     *
     * To reset to the default, set this to false.
     */
    asc?: boolean;
    /**
     * The file ID of the file to use as the cover for the collection.
     *
     * To reset to the default cover, set this to 0.
     */
    coverID?: number;
    /**
     * The layout type for the public collection display.
     *
     * Expected to be one of: "masonry", "grouped", "continuous", "trip".
     */
    layout?: string;
}

/**
 * Zod schema for {@link CollectionPublicMagicMetadataData}.
 */
export const CollectionPublicMagicMetadataData = z.looseObject({
    asc: z.boolean().nullish().transform(nullToUndefined),
    coverID: z.number().nullish().transform(nullToUndefined),
    layout: z.string().nullish().transform(nullToUndefined),
});

/**
 * Per-sharee mutable metadata associated with a shared {@link Collection}.
 *
 * [Note: Share specific metadata]
 *
 * When a collection is shared with a particular user, then remote creates a new
 * "share" entity defined by the (collectionID, fromUserID, toUserID) tuple
 * (this entity is not exposed to us directly, but it is helpful to know the
 * underlying implementation for this discussion).
 *
 * Remote also allows us to store mutable metadata (aka "magic metadata") with
 * each such share entity. This effectively acts as a private space where each
 * user with whom a collection has been shared can store and mutate metadata
 * about this shared collection without affecting either the owner or other
 * users with whom the collection has been shared.
 */
export interface CollectionShareeMagicMetadataData {
    /**
     * The (sharee specific) visibility of the collection.
     *
     * Expected to be one of {@link ItemVisibility}.
     */
    visibility?: number;
    /**
     * An override to the sort ordering used for the collection by the sharee.
     *
     * Expected to be one of {@link CollectionOrder}.
     */
    order?: number;
}

/**
 * Zod schema for {@link CollectionShareeMagicMetadataData}.
 */
export const CollectionShareeMagicMetadataData = z.looseObject({
    visibility: z.number().nullish().transform(nullToUndefined),
    order: z.number().nullish().transform(nullToUndefined),
});
