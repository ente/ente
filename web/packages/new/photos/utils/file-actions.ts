import type { GalleryBarMode } from "ente-new/photos/components/gallery/reducer";
import {
    PseudoCollectionID,
    type CollectionSummary,
} from "ente-new/photos/services/collection-summary";

/**
 * Actions that can be performed on files via the context menu.
 *
 * These correspond to the same operations available in SelectedFileOptions.
 */
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

/**
 * Context needed to determine which file actions should be available.
 */
interface FileActionContext {
    /** The current bar mode (albums, hidden-albums, archive-albums, people). */
    barMode?: GalleryBarMode;
    /** Whether we're in search mode. */
    isInSearchMode: boolean;
    /**
     * The collection summary for the current view.
     *
     * Will be undefined if we're in people section or showing search results.
     */
    collectionSummary: CollectionSummary | undefined;
    /**
     * Whether every selected file is owned by the current user.
     */
    hasOnlyOwnFiles: boolean;
    /**
     * Whether to show the "Add Person" action.
     *
     * This depends on ML being enabled and having named people.
     */
    showAddPerson: boolean;
    /**
     * Whether to show the "Edit Location" action.
     *
     * This depends on every selected file being owned.
     */
    showEditLocation: boolean;
}

/**
 * Returns the list of available file actions based on the current context.
 *
 * This function encapsulates the conditional logic from SelectedFileOptions
 * to enable reuse in both the selection bar and the context menu.
 */
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

    // Insert "addPerson" before modification actions if enabled
    // (not applicable for trash since you can't add people to trashed files)
    if (showAddPerson && collectionSummary?.id !== PseudoCollectionID.trash) {
        insertAddPersonBeforeModifications(actions);
    }

    return actions;
}

/**
 * Returns base actions without the "addPerson" action.
 */
function getBaseActions(
    barMode: GalleryBarMode | undefined,
    isInSearchMode: boolean,
    collectionSummary: CollectionSummary | undefined,
    hasOnlyOwnFiles: boolean,
    showEditLocation: boolean,
): FileContextAction[] {
    // Search mode actions
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

    // People mode actions
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

    // Trash actions
    if (collectionSummary?.id === PseudoCollectionID.trash) {
        return ["restore", "deletePermanently"];
    }

    // Uncategorized actions
    if (collectionSummary?.attributes.has("uncategorized")) {
        const actions: FileContextAction[] = ["download"];
        if (hasOnlyOwnFiles) {
            actions.push("moveToAlbum", "trash");
        }
        return actions;
    }

    // Shared incoming actions
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

    // Hidden albums mode actions
    if (barMode === "hidden-albums") {
        return ["download", "unhide", "trash"];
    }

    // Default (normal albums) actions
    const isUserFavorites =
        !!collectionSummary?.attributes.has("userFavorites");
    const isArchiveItems =
        collectionSummary?.id === PseudoCollectionID.archiveItems;

    const actions: FileContextAction[] = [];

    // Favorite/unfavorite action shown when not in archive.
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

/**
 * Inserts "sendLink" before "download" if present, else prepends it.
 */
function insertSendLinkBeforeDownload(actions: FileContextAction[]): void {
    const downloadIndex = actions.indexOf("download");
    if (downloadIndex !== -1) {
        actions.splice(downloadIndex, 0, "sendLink");
    } else {
        actions.unshift("sendLink");
    }
}

/**
 * Actions that modify file visibility or collection membership.
 * "addPerson" is inserted before the first of these actions.
 */
const modificationActions: FileContextAction[] = [
    "archive",
    "unarchive",
    "hide",
    "unhide",
    "trash",
    "moveToAlbum",
    "removeFromAlbum",
];

/**
 * Inserts "addPerson" before the first modification action in the array.
 */
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
