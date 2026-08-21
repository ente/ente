import type { GalleryBarMode } from "@/components/gallery/reducer";
import {
    PseudoCollectionID,
    type CollectionSummary,
} from "ente-new/photos/services/collection-summary";

export type FileContextAction =
    | "sendLink"
    | "download"
    | "fixTime"
    | "editLocation"
    | "favorite"
    | "unfavorite"
    | "archive"
    | "unarchive"
    | "hide"
    | "unhide"
    | "trash"
    | "deletePermanently"
    | "restore"
    | "addToAlbum"
    | "moveToAlbum"
    | "removeFromAlbum"
    | "addPerson";

interface FileActionContext {
    barMode?: GalleryBarMode;
    isInSearchMode: boolean;
    collectionSummary: CollectionSummary | undefined;
    hasOnlyOwnFiles: boolean;
    showAddPerson: boolean;
    showEditLocation: boolean;
}

export function getAvailableFileActions(
    context: FileActionContext,
): FileContextAction[] {
    const {
        barMode,
        isInSearchMode,
        collectionSummary,
        hasOnlyOwnFiles,
        showAddPerson,
        showEditLocation,
    } = context;

    const actions = getBaseActions(
        barMode,
        isInSearchMode,
        collectionSummary,
        hasOnlyOwnFiles,
        showEditLocation,
    );

    if (hasOnlyOwnFiles && collectionSummary?.id !== PseudoCollectionID.trash) {
        insertSendLinkBeforeDownload(actions);
    }

    if (showAddPerson && collectionSummary?.id !== PseudoCollectionID.trash) {
        insertAddPersonBeforeModifications(actions);
    }

    return actions;
}

function getBaseActions(
    barMode: GalleryBarMode | undefined,
    isInSearchMode: boolean,
    collectionSummary: CollectionSummary | undefined,
    hasOnlyOwnFiles: boolean,
    showEditLocation: boolean,
): FileContextAction[] {
    if (isInSearchMode) {
        const actions: FileContextAction[] = ["favorite"];
        if (hasOnlyOwnFiles) {
            actions.push("fixTime");
        }
        if (showEditLocation) {
            actions.push("editLocation");
        }
        actions.push("download", "addToAlbum");
        if (hasOnlyOwnFiles) {
            actions.push("archive", "hide", "trash");
        }
        return actions;
    }

    if (barMode === "people") {
        const actions: FileContextAction[] = [
            "favorite",
            "download",
            "addToAlbum",
        ];
        if (hasOnlyOwnFiles) {
            actions.push("archive", "hide", "trash");
        }
        return actions;
    }

    if (collectionSummary?.id === PseudoCollectionID.trash) {
        return ["restore", "deletePermanently"];
    }

    // Incoming summaries also retain their underlying collection type,
    // so shared actions must take precedence over type-specific actions.
    if (collectionSummary?.attributes.has("sharedIncoming")) {
        const actions: FileContextAction[] = [
            "favorite",
            "download",
            "addToAlbum",
        ];
        if (
            hasOnlyOwnFiles ||
            collectionSummary.attributes.has("sharedIncomingAdmin")
        ) {
            actions.push("removeFromAlbum");
        }
        return actions;
    }

    if (collectionSummary?.attributes.has("uncategorized")) {
        const actions: FileContextAction[] = ["download"];
        if (hasOnlyOwnFiles) {
            actions.push("moveToAlbum", "trash");
        }
        return actions;
    }

    if (barMode === "hidden-albums") {
        return ["download", "addToAlbum", "unhide", "trash"];
    }

    const isUserFavorites =
        !!collectionSummary?.attributes.has("userFavorites");
    const isArchiveItems =
        collectionSummary?.id === PseudoCollectionID.archiveItems;

    const actions: FileContextAction[] = [];

    if (isUserFavorites) {
        actions.push("unfavorite");
    } else if (!isArchiveItems) {
        actions.push("favorite");
    }

    if (hasOnlyOwnFiles) {
        actions.push("fixTime");
    }
    if (showEditLocation) {
        actions.push("editLocation");
    }
    actions.push("download", "addToAlbum");

    if (collectionSummary?.id === PseudoCollectionID.all) {
        if (hasOnlyOwnFiles) {
            actions.push("archive");
        }
    } else if (isArchiveItems) {
        if (hasOnlyOwnFiles) {
            actions.push("unarchive");
        }
    } else if (!isUserFavorites) {
        if (hasOnlyOwnFiles) {
            actions.push("moveToAlbum");
        }
        actions.push("removeFromAlbum");
    }

    if (hasOnlyOwnFiles) {
        actions.push("hide", "trash");
    }

    return actions;
}

function insertSendLinkBeforeDownload(actions: FileContextAction[]): void {
    const downloadIndex = actions.indexOf("download");
    if (downloadIndex !== -1) {
        actions.splice(downloadIndex, 0, "sendLink");
    } else {
        actions.unshift("sendLink");
    }
}

const modificationActions: FileContextAction[] = [
    "archive",
    "unarchive",
    "hide",
    "unhide",
    "trash",
    "moveToAlbum",
    "removeFromAlbum",
];

function insertAddPersonBeforeModifications(
    actions: FileContextAction[],
): void {
    const insertIndex = actions.findIndex((a) =>
        modificationActions.includes(a),
    );
    if (insertIndex !== -1) {
        actions.splice(insertIndex, 0, "addPerson");
    } else {
        actions.push("addPerson");
    }
}
