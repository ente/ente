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

export interface PersonalNoteData {
    title: string;
    content: string;
}

export interface AccountCredentialData {
    name: string;
    username: string;
    password: string;
    notes?: string;
}

export interface PhysicalRecordData {
    name: string;
    location: string;
    notes?: string;
}

export interface EmergencyContactData {
    name: string;
    contactDetails: string;
    notes?: string;
}

export interface GenericFileData {
    name: string;
    fileSize?: number;
    hasObject?: boolean;
}

type LockerItemData =
    | PersonalNoteData
    | AccountCredentialData
    | PhysicalRecordData
    | EmergencyContactData
    | GenericFileData;

export interface LockerItem {
    id: number;
    ownerID?: number;
    type: LockerItemType;
    data: LockerItemData;
    collectionID: number;
    collectionIDs: number[];
    createdAt?: number;
    updatedAt?: number;
    deleteBy?: number;
}

export interface LockerCollection {
    id: number;
    name: string;
    owner: LockerCollectionParticipant;
    sharees: LockerCollectionParticipant[];
    items: LockerItem[];
    type: string;
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

const canRestoreToCollection = (
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

export const restoreTargetLockerCollections = (
    collections: LockerCollection[],
    currentUserID: number | undefined,
) =>
    sortLockerCollections(collections).filter((collection) =>
        canRestoreToCollection(collection, currentUserID),
    );

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
