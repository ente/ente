/**
 * The types of items supported by Ente Locker.
 *
 * The four info types match the mobile app's InfoType enum in
 * mobile/apps/locker/lib/models/info/info_item.dart.
 *
 * "file" represents a regular file (music, document, image, etc.) that
 * does not carry structured info metadata.
 */
import { t } from "i18next";

export type LockerItemType =
    | "note"
    | "accountCredential"
    | "physicalRecord"
    | "emergencyContact"
    | "file";

export type LockerCollectionParticipantRole =
    | "VIEWER"
    | "COLLABORATOR"
    | "ADMIN"
    | "OWNER";

export interface LockerCollectionParticipant {
    id: number;
    email?: string;
    role?: LockerCollectionParticipantRole;
}

/** Data for a personal note. */
export interface PersonalNoteData {
    title: string;
    content: string;
}

/** Data for an account credential (password entry). */
export interface AccountCredentialData {
    name: string;
    username: string;
    password: string;
    notes?: string;
}

/** Data for a physical record. */
export interface PhysicalRecordData {
    name: string;
    location: string;
    notes?: string;
}

/** Data for an emergency contact. */
export interface EmergencyContactData {
    name: string;
    contactDetails: string;
    notes?: string;
}

/** Data for a generic file (non-info item). */
export interface GenericFileData {
    /** Display name (from metadata or filename). */
    name: string;
    /** File size in bytes, if known. */
    fileSize?: number;
    /** Whether this item has a downloadable backing object. */
    hasObject?: boolean;
}

/** Union of all item data types. */
export type LockerItemData =
    | PersonalNoteData
    | AccountCredentialData
    | PhysicalRecordData
    | EmergencyContactData
    | GenericFileData;

/**
 * A decrypted item from the Locker.
 *
 * Each item corresponds to an encrypted file in a collection. Info items
 * have structured data extracted from pubMagicMetadata.info; generic files
 * have a name extracted from the file's metadata.
 */
export interface LockerItem {
    /** The uploaded file ID (unique identifier). */
    id: number;
    /** The owner of the file/item, when known. */
    ownerID?: number;
    /** The type of this item. */
    type: LockerItemType;
    /** The type-specific data payload. */
    data: LockerItemData;
    /** The collection this item belongs to. */
    collectionID: number;
    /** All collections this item belongs to, when known. */
    collectionIDs: number[];
    /** Epoch microseconds when this item was created. */
    createdAt?: number;
    /** Epoch microseconds when this item was last updated. */
    updatedAt?: number;
    /**
     * Epoch microseconds after which a trashed item will be permanently
     * deleted. Only set for items fetched from the trash.
     */
    deleteBy?: number;
}

/**
 * A decrypted Locker collection.
 *
 * Collections group related items together (similar to folders).
 */
export interface LockerCollection {
    /** The collection ID. */
    id: number;
    /** The decrypted display name. */
    name: string;
    /** The owner of the collection. */
    owner: LockerCollectionParticipant;
    /** Collection participants excluding the owner. */
    sharees: LockerCollectionParticipant[];
    /** The items in this collection. */
    items: LockerItem[];
    /** The collection type (e.g. "album", "folder"). */
    type: string;
    /** Whether this collection is shared with other users. */
    isShared: boolean;
}

export interface LockerUploadCandidate {
    file: File;
    relativePath?: string;
    suggestedCollectionNames: string[];
}

const IMPORTANT_COLLECTION_TYPE = "favorites";
const UNCATEGORIZED_COLLECTION_TYPE = "uncategorized";

export const isImportantCollection = (collection: LockerCollection) =>
    collection.type === IMPORTANT_COLLECTION_TYPE;

export const isUncategorizedCollection = (collection: LockerCollection) =>
    collection.type === UNCATEGORIZED_COLLECTION_TYPE;

export const isCollectionOwner = (
    collection: LockerCollection,
    currentUserID: number | undefined,
) => currentUserID !== undefined && collection.owner.id === currentUserID;

export const canRestoreToCollection = (
    collection: LockerCollection,
    currentUserID: number | undefined,
) =>
    isCollectionOwner(collection, currentUserID) &&
    !isUncategorizedCollection(collection);

export const canEditCollection = (
    collection: LockerCollection,
    currentUserID: number | undefined,
) =>
    isCollectionOwner(collection, currentUserID) &&
    !isImportantCollection(collection) &&
    !isUncategorizedCollection(collection);

export const canOpenCollectionSharing = (collection: LockerCollection) =>
    !isImportantCollection(collection) &&
    !isUncategorizedCollection(collection);

export const canLeaveCollection = (
    collection: LockerCollection,
    currentUserID: number | undefined,
) =>
    !isImportantCollection(collection) &&
    !isCollectionOwner(collection, currentUserID);

export const isLockerItemOwner = (
    item: LockerItem,
    currentUserID: number | undefined,
) =>
    currentUserID !== undefined &&
    (item.ownerID ?? currentUserID) === currentUserID;

export const canShareLockerFileLink = (
    item: LockerItem,
    currentUserID: number | undefined,
) => isLockerItemOwner(item, currentUserID);

export const canManageCollectionSharing = (
    collection: LockerCollection,
    currentUserID: number | undefined,
) =>
    canOpenCollectionSharing(collection) &&
    isCollectionOwner(collection, currentUserID);

export const sortLockerCollections = (collections: LockerCollection[]) =>
    [...collections].sort((a, b) => {
        if (isImportantCollection(a) && !isImportantCollection(b)) return -1;
        if (!isImportantCollection(a) && isImportantCollection(b)) return 1;
        const aHasItems = a.items.length > 0;
        const bHasItems = b.items.length > 0;
        if (aHasItems && !bHasItems) return -1;
        if (!aHasItems && bHasItems) return 1;
        return a.name.localeCompare(b.name, undefined, { sensitivity: "base" });
    });

export const visibleLockerCollections = (collections: LockerCollection[]) =>
    sortLockerCollections(collections);

export const restoreTargetLockerCollections = (
    collections: LockerCollection[],
    currentUserID: number | undefined,
) =>
    visibleLockerCollections(collections).filter((collection) =>
        canRestoreToCollection(collection, currentUserID),
    );

/**
 * Get the display title for a locker item.
 */
export const getItemTitle = (item: LockerItem): string => {
    switch (item.type) {
        case "note": {
            const data = item.data as PersonalNoteData;
            return data.title || t("personalNote");
        }
        case "accountCredential": {
            const data = item.data as AccountCredentialData;
            return data.name || t("secret");
        }
        case "physicalRecord": {
            const data = item.data as PhysicalRecordData;
            return data.name || t("thing");
        }
        case "emergencyContact": {
            const data = item.data as EmergencyContactData;
            return data.name || t("emergencyContact");
        }
        case "file": {
            const data = item.data as GenericFileData;
            return data.name || t("document");
        }
    }
};

export const hasDownloadableObject = (item: LockerItem) =>
    item.type === "file" && (item.data as GenericFileData).hasObject !== false;
