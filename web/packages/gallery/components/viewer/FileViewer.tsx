import { Navigation03Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import AddIcon from "@mui/icons-material/Add";
import ArchiveOutlinedIcon from "@mui/icons-material/ArchiveOutlined";
import ContentCopyIcon from "@mui/icons-material/ContentCopy";
import DeleteIcon from "@mui/icons-material/Delete";
import EditIcon from "@mui/icons-material/Edit";
import FileDownloadOutlinedIcon from "@mui/icons-material/FileDownloadOutlined";
import FullscreenExitOutlinedIcon from "@mui/icons-material/FullscreenExitOutlined";
import FullscreenOutlinedIcon from "@mui/icons-material/FullscreenOutlined";
import UnArchiveIcon from "@mui/icons-material/Unarchive";
import {
    Dialog,
    DialogContent,
    DialogTitle,
    Menu,
    MenuItem,
    Stack,
    styled,
    Typography,
    type ModalProps,
} from "@mui/material";
import type { LocalUser } from "ente-accounts/services/user";
import { isDesktop } from "ente-base/app";
import { SpacedRow } from "ente-base/components/containers";
import { InlineErrorIndicator } from "ente-base/components/ErrorIndicator";
import { TitledMiniDialog } from "ente-base/components/MiniDialog";
import { DialogCloseIconButton } from "ente-base/components/mui/DialogCloseIconButton";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { useInterval, useIsSmallWidth } from "ente-base/components/utils/hooks";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import { lowercaseExtension } from "ente-base/file-name";
import { formattedListJoin, ut } from "ente-base/i18n";
import log from "ente-base/log";
import {
    FileInfo,
    type FileInfoExif,
    type FileInfoProps,
} from "ente-gallery/components/FileInfo";
import type { Collection } from "ente-media/collection";
import {
    fileFileName,
    ItemVisibility,
    metadataHash,
} from "ente-media/file-metadata";
import { FileType } from "ente-media/file-type";
import type { EnteFile } from "ente-media/file.js";
import { isHEICExtension, needsJPEGConversion } from "ente-media/formats";
import {
    ImageEditorOverlay,
    type ImageEditorOverlayProps,
} from "ente-new/photos/components/ImageEditorOverlay";
import { getCollectionByID } from "ente-new/photos/services/collection";
import type { CollectionSummaries } from "ente-new/photos/services/collection-summary";
import type { Comment } from "ente-new/photos/services/comment";
import { addReaction, deleteReaction } from "ente-new/photos/services/reaction";
import {
    getAnonProfiles,
    getUnifiedSocialDiff,
    type UnifiedReaction,
} from "ente-new/photos/services/social";
import { t } from "i18next";
import React, {
    useCallback,
    useEffect,
    useMemo,
    useRef,
    useState,
} from "react";
import { CommentsSidebar } from "./CommentsSidebar";
import {
    fileInfoExifForFile,
    updateItemDataAlt,
    type ItemData,
} from "./data-source";
import { LikeAlbumSelectorModal } from "./LikeAlbumSelectorModal";
import { LikesSidebar } from "./LikesSidebar";
import {
    FileViewerPhotoSwipe,
    moreButtonID,
    moreMenuID,
    resetMoreMenuButtonOnMenuClose,
    type FileViewerPhotoSwipeDelegate,
} from "./photoswipe";

const fileViewerBackStateKey = "__enteFileViewerBackState";

const addFileViewerBackStateMarker = (state: unknown, marker: string) =>
    state && typeof state == "object"
        ? {
              ...(state as Record<string, unknown>),
              [fileViewerBackStateKey]: marker,
          }
        : { [fileViewerBackStateKey]: marker };

const hasFileViewerBackStateMarker = (state: unknown, marker: string) =>
    !!state &&
    typeof state == "object" &&
    (state as Record<string, unknown>)[fileViewerBackStateKey] == marker;

/**
 * Derived data for a file that is needed to display the file viewer controls
 * etc associated with the file.
 *
 * This is recomputed on-demand each time the slide changes.
 */
export interface FileViewerFileAnnotation {
    /**
     * The id of the file whose annotation this is.
     */
    fileID: number;
    /**
     * `true` if this file is owned by the logged in user (if any).
     */
    isOwnFile: boolean;
    /**
     * `true` if the toggle favorite action should be shown for this file.
     */
    showFavorite: boolean;
    /**
     * Set if the download action should be shown for this file.
     *
     * - When "bar", the action button is shown among the bar icons.
     *
     * - When "menu", the action is shown as a more menu entry.
     *
     * Note: "bar" should only be set if {@link haveUser} is also true.
     */
    showDownload: "bar" | "menu" | undefined;
    /**
     * `true` if the delete action should be shown for this file.
     */
    showDelete: boolean;
    /**
     * `true` if the toggle archive action should be shown for this file.
     */
    showArchive: boolean;
    /**
     * `true` if the copy image action should be shown for this file.
     */
    showCopyImage: boolean;
    /**
     * `true` if this is an image which can be edited, _and_ editing is
     * possible, and the edit action should therefore be shown for this file.
     */
    showEditImage: boolean;
}

/**
 * A file, its annotation, and its item data, in a nice cosy box.
 */
export interface FileViewerAnnotatedFile {
    file: EnteFile;
    annotation: FileViewerFileAnnotation;
    itemData: ItemData;
}

/** The type of sidebar to open initially in the file viewer. */
export type FileViewerInitialSidebar = "likes" | "comments";

export type FileViewerProps = ModalVisibilityProps & {
    /**
     * The currently logged in user, if any.
     *
     * - If we're running in the context of the photos app, then this should be
     *   set to the currently logged in user.
     *
     * - If we're running in a viewer without account context, then this should
     *   not be set.
     *
     * See: [Note: Gallery children can assume user]
     */
    user?: LocalUser;
    /**
     * The list of files that are currently being displayed in the context in
     * which the file viewer was invoked.
     *
     * Although the file viewer is called on to display a particular file
     * (specified by the {@link initialIndex} prop), the viewer is always used
     * in the context of a an album, or search results, or some other arbitrary
     * list of files. The {@link files} prop sets this underlying list of files.
     *
     * After the initial file has been shown, the user can navigate through the
     * other files from within the viewer by using the arrow buttons.
     */
    files: EnteFile[];
    /**
     * The index of the file that should be initially shown.
     *
     * Subsequently the user may navigate between files by using the controls
     * provided within the file viewer itself.
     */
    initialIndex: number;
    /**
     * If set, the specified sidebar will be opened when the file viewer opens.
     */
    initialSidebar?: FileViewerInitialSidebar;
    /**
     * If set, the comments sidebar will scroll to and highlight this comment.
     * Only used when initialSidebar is "comments".
     */
    highlightCommentID?: string;
    /**
     * If true then the viewer does not show controls for downloading the file.
     */
    disableDownload?: boolean;
    /**
     * If true then the fullscreen button is shown as a primary action button
     * in the toolbar instead of being hidden in the more menu.
     */
    showFullscreenButton?: boolean;
    /**
     * `true` when we are viewing files in an album that the user does not own.
     */
    isInIncomingSharedCollection?: boolean;
    /**
     * `true` when we are viewing files in the Trash.
     */
    isInTrashSection?: boolean;
    /**
     * `true` when we are viewing files in the hidden section.
     */
    isInHiddenSection?: boolean;
    /**
     * File IDs of all the files that the user has marked as a favorite.
     *
     * See also {@link onToggleFavorite}.
     */
    favoriteFileIDs?: Set<number>;
    /**
     * File IDs of for which an update of its favorite status is pending (e.g.
     * due to a toggle favorite action in the file viewer).
     *
     * See also {@link favoriteFileIDs} and {@link onToggleFavorite}.
     */
    pendingFavoriteUpdates?: Set<number>;
    /**
     * File IDs of for which an update of its visibility is pending (e.g. due to
     * a toggle archived action in the file viewer).
     *
     * See also {@link onFileVisibilityUpdate}.
     */
    pendingVisibilityUpdates?: Set<number>;
    /**
     * A mapping from file IDs to the IDs of the normal (non-hidden) collections
     * that they are a part of.
     */
    fileNormalCollectionIDs?: FileInfoProps["fileCollectionIDs"];
    /**
     * A mapping from file IDs to all collection IDs that they are a part of.
     */
    fileCollectionIDs?: FileInfoProps["fileCollectionIDs"];
    /**
     * IDs of hidden collections.
     */
    hiddenCollectionIDs?: FileInfoProps["hiddenCollectionIDs"];
    /**
     * Collection summaries indexed by their IDs.
     */
    collectionSummaries?: CollectionSummaries;
    /**
     * Called when there was some update performed within the file viewer that
     * necessitates us to pull the latest updates with remote.
     *
     * This is called  when the file viewer is closing if any changes were made
     * in the file info panel of the file viewer for any of the files that the
     * user was viewing (e.g. if they changed the caption).
     *
     * Those changes have already been applied to both remote, and likely
     * already also to our local state via {@link onRemoteFilesPull}. This this
     * callback is to trigger a full pull so that any discrepancies in local
     * database also gets up to speed if needed.
     *
     * If we're in a context where edits are not possible, e.g. {@link user} is
     * not defined, then this prop is not used and need not be provided.
     */
    onTriggerRemotePull?: () => void;
    /**
     * Called when an action in the file viewer requires us to pull the local
     * files and collections with remote.
     *
     * Unlike {@link onTriggerRemotePull}, which is a trigger, this function
     * returns a promise that will settle once the pull has completed, and thus
     * can be used in interactive operations that indicate activity to the user.
     *
     * See also: [Note: Full remote pull vs files pull]
     */
    onRemoteFilesPull?: () => Promise<void>;
    /**
     * Called when the user performs an action which does not otherwise have any
     * immediate visual impact, to acknowledge it.
     *
     * See: [Note: Visual feedback to acknowledge user actions]
     */
    onVisualFeedback: () => void;
    /**
     * Called when the favorite status of given {@link file} should be toggled
     * from its current value.
     *
     * The favorite toggle button is shown only if all three of
     * {@link favoriteFileIDs}, {@link pendingFavoriteUpdates} and
     * {@link onToggleFavorite} are provided.
     */
    onToggleFavorite?: (file: EnteFile) => Promise<void>;
    /**
     * Called when {@link visibility} of the given {@link file} should be
     * updated (when the user activates toggle archived action).
     *
     * The toggle archived action is shown only if both
     * {@link pendingVisibilityUpdates} and {@link onFileVisibilityUpdate} are
     * provided.
     */
    onFileVisibilityUpdate?: (
        file: EnteFile,
        visibility: ItemVisibility,
    ) => Promise<void>;
    /**
     * Called when the given {@link file} should be downloaded.
     *
     * If this is not provided then the download action will not be shown.
     */
    onDownload?: (file: EnteFile) => void;
    /**
     * Called when the given {@link file} should be shared via quick link.
     *
     * If this is not provided then the send link action will not be shown.
     */
    onSendLink?: (file: EnteFile) => void;
    /**
     * Called when the given {@link file} should be deleted.
     *
     * If this is not provided then the delete action will not be shown.
     */
    onDelete?: (file: EnteFile) => Promise<void>;
    /**
     * Called when the user edits an image in the image editor and asks us to
     * save their edits as a copy.
     *
     * Editing is disabled if this is not provided.
     *
     * See {@link onSaveEditedCopy} in the {@link ImageEditorOverlay} props for
     * documentation about the parameters.
     */
    onSaveEditedImageCopy?: ImageEditorOverlayProps["onSaveEditedCopy"];

    onAddFileToCollection?: (
        file: EnteFile,
        sourceCollectionSummaryID?: number,
    ) => void;
    /**
     * The ID of the currently active collection, if any (e.g., when viewing an album).
     */
    activeCollectionID?: number;
    /**
     * If set, overrides whether browser back should be consumed to close the
     * viewer.
     *
     * By default this is disabled.
     */
    shouldCloseOnBrowserBack?: boolean;
    /**
     * If `true`, disables closing the viewer with the Escape key.
     */
    disableEscapeClose?: boolean;
    /**
     * `true` if comments and reactions are enabled.
     * Defaults to `true`.
     */
    enableComment?: boolean;
    /**
     * `true` if the comments and reactions feature is enabled for the user.
     *
     * When `false`, the like and comment buttons will be hidden for logged-in
     * users. Defaults to `true`.
     */
    isCommentsFeatureEnabled?: boolean;
} & Pick<
        FileInfoProps,
        "collectionNameByID" | "onSelectCollection" | "onSelectPerson"
    >;

/**
 * A PhotoSwipe based image, live photo and video viewer.
 */
export const FileViewer: React.FC<FileViewerProps> = ({
    open,
    onClose,
    user,
    files,
    initialIndex,
    initialSidebar,
    highlightCommentID,
    disableDownload,
    showFullscreenButton,
    isInIncomingSharedCollection,
    isInTrashSection,
    isInHiddenSection,
    favoriteFileIDs,
    pendingFavoriteUpdates,
    pendingVisibilityUpdates,
    fileNormalCollectionIDs,
    fileCollectionIDs,
    hiddenCollectionIDs,
    collectionSummaries,
    collectionNameByID,
    onTriggerRemotePull,
    onRemoteFilesPull,
    onVisualFeedback,
    onToggleFavorite,
    onFileVisibilityUpdate,
    onDownload,
    onSendLink,
    onDelete,
    onSelectCollection,
    onSelectPerson,
    onSaveEditedImageCopy,
    onAddFileToCollection,
    activeCollectionID,
    shouldCloseOnBrowserBack: shouldCloseOnBrowserBackOverride,
    disableEscapeClose = false,
    enableComment = true,
    isCommentsFeatureEnabled = true,
}) => {
    const { onGenericError } = useBaseContext();
    const shouldCloseOnBrowserBack = shouldCloseOnBrowserBackOverride ?? false;

    // There are 3 things involved in this dance:
    //
    // 1. Us, "FileViewer". We're a React component.
    // 2. The custom PhotoSwipe wrapper, "FileViewerPhotoSwipe". It is a class.
    // 3. The delegate, "FileViewerPhotoSwipeDelegate".
    //
    // The delegate acts as a bridge between us and (our custom) photoswipe
    // class, to avoid recreating the class each time a "dynamic" prop changes.
    // The delegate has a stable identity, we just keep updating the callback
    // functions that it holds.
    //
    // The word "dynamic" here means a prop on whose change we should not
    // recreate the photoswipe dialog.
    const delegateRef = useRef<
        FileViewerPhotoSwipeDelegate<FileViewerAnnotatedFile> | undefined
    >(undefined);

    // We also need to maintain a ref to the currently displayed dialog since we
    // might need to ask it to refresh its contents.
    const psRef = useRef<
        FileViewerPhotoSwipe<FileViewerAnnotatedFile> | undefined
    >(undefined);
    const handleCloseRef = useRef<() => void>(() => undefined);
    const browserBackStateRef = useRef<string | undefined>(undefined);

    // Whenever we get a callback from our custom PhotoSwipe instance, we also
    // get the active file on which that action was performed as an argument. We
    // save it as the `activeAnnotatedFile` state so that the rest of our React
    // tree can use it.
    //
    // This is not guaranteed, or even intended, to be in sync with the active
    // file shown within the file viewer. All that this guarantees is this will
    // refer to the file on which the last user initiated action was performed.
    const [activeAnnotatedFile, setActiveAnnotatedFile] = useState<
        FileViewerAnnotatedFile | undefined
    >(undefined);

    // With semantics similar to `activeAnnotatedFile`, this is the exif data
    // associated with the `activeAnnotatedFile`, if any.
    const [activeFileExif, setActiveFileExif] = useState<
        FileInfoExif | undefined
    >(undefined);
    const activeFileExifFileIDRef = useRef<number | undefined>(undefined);

    const refreshActiveFileExif = useCallback((file: EnteFile) => {
        const fileID = file.id;
        activeFileExifFileIDRef.current = fileID;
        setActiveFileExif(
            fileInfoExifForFile(file, (exif) => {
                if (activeFileExifFileIDRef.current == fileID) {
                    setActiveFileExif(exif);
                }
            }),
        );
    }, []);

    const [openFileInfo, setOpenFileInfo] = useState(false);
    const [fileInfoNavigationLocked, setFileInfoNavigationLocked] =
        useState(false);
    const [openComments, setOpenComments] = useState(false);
    const [openLikes, setOpenLikes] = useState(false);
    const [openLikeAlbumSelector, setOpenLikeAlbumSelector] = useState(false);
    const [moreMenuAnchorEl, setMoreMenuAnchorEl] =
        useState<HTMLElement | null>(null);
    const [openImageEditor, setOpenImageEditor] = useState(false);
    const [openConfirmDelete, setOpenConfirmDelete] = useState(false);
    const [openShortcuts, setOpenShortcuts] = useState(false);

    const [isFullscreen, setIsFullscreen] = useState(false);

    // Map of file ID to map of collection ID to array of comments.
    // For gallery view, we fetch comments from all collections.
    // For collection view, we only fetch comments from that collection.
    const [fileComments, setFileComments] = useState<
        Map<number, Map<number, Comment[]>>
    >(new Map());

    // Map of file ID to map of collection ID to array of all reactions.
    // Includes both file reactions and comment reactions.
    const [allReactions, setAllReactions] = useState<
        Map<number, Map<number, UnifiedReaction[]>>
    >(new Map());

    // Map of user ID to email for displaying reaction/comment authors.
    // Built from collection owner and sharees when fetching social data.
    const [userIDToEmail, setUserIDToEmail] = useState<Map<number, string>>(
        new Map(),
    );

    // Map of anon user ID to decrypted user name for anonymous users.
    const [anonUserNames, setAnonUserNames] = useState<Map<string, string>>(
        new Map(),
    );

    // Ref for fileComments to use in callbacks
    const fileCommentsRef = useRef(fileComments);
    useEffect(() => {
        fileCommentsRef.current = fileComments;
    }, [fileComments]);

    // Ref for allReactions to use in callbacks
    const allReactionsRef = useRef(allReactions);
    useEffect(() => {
        allReactionsRef.current = allReactions;
    }, [allReactions]);

    // Ref for collectionSummaries to use in callbacks without causing recreations
    const collectionSummariesRef = useRef(collectionSummaries);
    useEffect(() => {
        collectionSummariesRef.current = collectionSummaries;
    }, [collectionSummaries]);

    // Ref for fileNormalCollectionIDs to use in callbacks without causing recreations
    const fileNormalCollectionIDsRef = useRef(fileNormalCollectionIDs);
    useEffect(() => {
        fileNormalCollectionIDsRef.current = fileNormalCollectionIDs;
    }, [fileNormalCollectionIDs]);

    // Cache for collection keys to avoid refetching during polling
    const collectionCacheRef = useRef<
        Map<
            number,
            {
                key: string;
                ownerID: number;
                ownerEmail?: string;
                sharees: { id: number; email?: string }[];
                hasPublicURLs: boolean;
            }
        >
    >(new Map());

    // Track whether we've already opened the initial sidebar for this open
    const hasOpenedInitialSidebarRef = useRef(false);

    // Open the initial sidebar when the file viewer opens with initialSidebar set
    useEffect(() => {
        if (open && initialSidebar && !hasOpenedInitialSidebarRef.current) {
            hasOpenedInitialSidebarRef.current = true;
            if (initialSidebar === "comments") {
                setOpenComments(true);
            } else {
                setOpenLikes(true);
            }
        }
        // Reset the flag when the viewer closes
        if (!open) {
            hasOpenedInitialSidebarRef.current = false;
        }
    }, [open, initialSidebar]);

    // Helper to get current user's file reactions from allReactions
    const getUserFileReactions = useCallback(
        (fileId: number): { collectionId: number; reactionId: string }[] => {
            if (!user?.id) return [];
            const fileReactionsMap = allReactionsRef.current.get(fileId);
            if (!fileReactionsMap) return [];

            const userReactions: {
                collectionId: number;
                reactionId: string;
            }[] = [];
            for (const [collectionId, reactions] of fileReactionsMap) {
                const userFileReaction = reactions.find((r) => {
                    if (
                        r.commentID ||
                        r.fileID !== fileId ||
                        r.reactionType !== "green_heart"
                    )
                        return false;
                    return r.userID === user.id;
                });
                if (userFileReaction) {
                    userReactions.push({
                        collectionId,
                        reactionId: userFileReaction.id,
                    });
                }
            }
            return userReactions;
        },
        [user?.id],
    );

    // If `true`, then we need to trigger a pull from remote when we close.
    const [, setNeedsRemotePull] = useState(false);

    const handleNeedsRemotePull = useCallback(
        () => setNeedsRemotePull(true),
        [],
    );

    const handleClose = useCallback(() => {
        if (document.fullscreenElement) void document.exitFullscreen();
        setNeedsRemotePull((needsPull) => {
            if (needsPull) onTriggerRemotePull?.();
            return false;
        });
        setOpenFileInfo(false);
        setFileInfoNavigationLocked(false);
        setOpenComments(false);
        setOpenLikes(false);
        setOpenLikeAlbumSelector(false);
        // No need to `resetMoreMenuButtonOnMenuClose` since we're closing
        // anyway and it'll be removed from the DOM.
        setMoreMenuAnchorEl(null);
        setOpenImageEditor(false);
        setOpenConfirmDelete(false);
        setOpenShortcuts(false);
        setIsFullscreen(false);
        onClose();
    }, [onTriggerRemotePull, onClose]);

    // Keep the latest close callback available to non-react event handlers
    // without forcing effects that register handlers to re-run.
    handleCloseRef.current = handleClose;

    const handleViewInfo = useCallback(
        (annotatedFile: FileViewerAnnotatedFile) => {
            refreshActiveFileExif(annotatedFile.file);
            setOpenFileInfo(true);
        },
        [refreshActiveFileExif],
    );

    useEffect(() => {
        if (openFileInfo && activeAnnotatedFile) {
            refreshActiveFileExif(activeAnnotatedFile.file);
        }
    }, [activeAnnotatedFile, openFileInfo, refreshActiveFileExif]);

    const handleFileInfoClose = useCallback(() => {
        setOpenFileInfo(false);
        setFileInfoNavigationLocked(false);
    }, []);

    const handleViewComments = useCallback(() => setOpenComments(true), []);

    const handleCommentsClose = useCallback(() => setOpenComments(false), []);

    // Handle a new comment being added
    const handleCommentAdded = useCallback((comment: Comment) => {
        const fileID = comment.fileID;
        if (!fileID) return;

        setFileComments((prev) => {
            const next = new Map(prev);
            const fileCommentsMap = new Map<number, Comment[]>(
                prev.get(fileID) ?? new Map(),
            );
            const collectionComments =
                fileCommentsMap.get(comment.collectionID) ?? [];
            fileCommentsMap.set(comment.collectionID, [
                ...collectionComments,
                comment,
            ]);
            next.set(fileID, fileCommentsMap);
            return next;
        });
    }, []);

    // Handle a comment being deleted
    const handleCommentDeleted = useCallback(
        (collectionID: number, commentID: string) => {
            const fileID = activeAnnotatedFile?.file.id;
            if (!fileID) return;

            setFileComments((prev) => {
                const next = new Map(prev);
                const fileCommentsMap = prev.get(fileID);
                if (fileCommentsMap) {
                    const updatedMap = new Map(fileCommentsMap);
                    const collectionComments =
                        updatedMap.get(collectionID) ?? [];
                    updatedMap.set(
                        collectionID,
                        collectionComments.map((c) =>
                            c.id === commentID ? { ...c, isDeleted: true } : c,
                        ),
                    );
                    next.set(fileID, updatedMap);
                }
                return next;
            });
        },
        [activeAnnotatedFile],
    );

    // Handle a comment reaction being added
    const handleCommentReactionAdded = useCallback(
        (reaction: UnifiedReaction) => {
            const fileID = activeAnnotatedFile?.file.id;
            if (!fileID) return;

            setAllReactions((prev) => {
                const next = new Map(prev);
                const fileReactionsMap = new Map<number, UnifiedReaction[]>(
                    prev.get(fileID) ?? new Map(),
                );
                const collectionReactions =
                    fileReactionsMap.get(reaction.collectionID) ?? [];
                fileReactionsMap.set(reaction.collectionID, [
                    ...collectionReactions,
                    reaction,
                ]);
                next.set(fileID, fileReactionsMap);
                return next;
            });
        },
        [activeAnnotatedFile],
    );

    // Handle a comment reaction being deleted
    const handleCommentReactionDeleted = useCallback(
        (collectionID: number, reactionID: string) => {
            const fileID = activeAnnotatedFile?.file.id;
            if (!fileID) return;

            setAllReactions((prev) => {
                const next = new Map(prev);
                const fileReactionsMap = prev.get(fileID);
                if (fileReactionsMap) {
                    const updatedMap = new Map(fileReactionsMap);
                    const collectionReactions =
                        updatedMap.get(collectionID) ?? [];
                    updatedMap.set(
                        collectionID,
                        collectionReactions.filter((r) => r.id !== reactionID),
                    );
                    next.set(fileID, updatedMap);
                }
                return next;
            });
        },
        [activeAnnotatedFile],
    );

    const handleViewLikes = useCallback(() => setOpenLikes(true), []);

    const handleLikesClose = useCallback(() => setOpenLikes(false), []);

    // Refs to access current state without causing re-renders
    // when used in callbacks that are dependencies of the PhotoSwipe effect.
    const activeAnnotatedFileRef = useRef(activeAnnotatedFile);
    activeAnnotatedFileRef.current = activeAnnotatedFile;

    // Called when the like button (heart) is clicked.
    // - If gallery view: show album selector (like) OR unlike selector/direct delete
    // - If collection view: toggle like in that collection
    const handleLikeClick = useCallback(() => {
        if (!user?.id) {
            return;
        }

        const file = activeAnnotatedFileRef.current?.file;
        if (!file) return;

        const fileId = file.id;
        const reactions = getUserFileReactions(fileId);
        const isGalleryView = !activeCollectionID || activeCollectionID === 0;

        if (isGalleryView) {
            // Gallery view - only consider shared collections
            const allCollectionIDs =
                fileNormalCollectionIDsRef.current?.get(fileId) ?? [];
            const collectionIDs = allCollectionIDs.filter((id) =>
                collectionSummariesRef.current
                    ?.get(id)
                    ?.attributes.has("shared"),
            );

            if (reactions.length === 0) {
                // Not liked in any collection
                if (collectionIDs.length === 1) {
                    // Single album - like directly without showing modal
                    const collectionId = collectionIDs[0]!;
                    void (async () => {
                        try {
                            const collection =
                                await getCollectionByID(collectionId);
                            const reactionId = await addReaction(
                                collectionId,
                                fileId,
                                "green_heart",
                                collection.key,
                            );
                            setAllReactions((prev) => {
                                const next = new Map(prev);
                                const fileReactionsMap = new Map<
                                    number,
                                    UnifiedReaction[]
                                >(prev.get(fileId) ?? new Map());
                                const collectionReactions =
                                    fileReactionsMap.get(collectionId) ?? [];
                                fileReactionsMap.set(collectionId, [
                                    ...collectionReactions,
                                    {
                                        id: reactionId,
                                        collectionID: collectionId,
                                        fileID: fileId,
                                        reactionType: "green_heart",
                                        userID: user.id,
                                        isDeleted: false,
                                        createdAt: Date.now() * 1000,
                                        updatedAt: Date.now() * 1000,
                                    },
                                ]);
                                next.set(fileId, fileReactionsMap);
                                return next;
                            });
                        } catch (e) {
                            log.error("Failed to add reaction", e);
                        }
                    })();
                } else {
                    // Multiple albums - show album selector
                    setOpenLikeAlbumSelector(true);
                }
            } else {
                // Liked in one or more collections - unlike from all
                void (async () => {
                    try {
                        const deletedReactionIds = new Set<string>();
                        for (const reaction of reactions) {
                            await deleteReaction(reaction.reactionId);
                            deletedReactionIds.add(reaction.reactionId);
                        }
                        setAllReactions((prev) => {
                            const next = new Map(prev);
                            const fileReactionsMap = prev.get(fileId);
                            if (fileReactionsMap) {
                                const updatedMap = new Map(fileReactionsMap);
                                for (const [
                                    collectionId,
                                    collectionReactions,
                                ] of updatedMap) {
                                    updatedMap.set(
                                        collectionId,
                                        collectionReactions.filter(
                                            (r) =>
                                                !deletedReactionIds.has(r.id),
                                        ),
                                    );
                                }
                                next.set(fileId, updatedMap);
                            }
                            return next;
                        });
                    } catch (e) {
                        log.error("Failed to delete reactions", e);
                    }
                })();
            }
        } else {
            // Collection view - toggle like in this specific collection
            const existingReaction = reactions.find(
                (r) => r.collectionId === activeCollectionID,
            );

            if (existingReaction) {
                // Already liked in this collection - delete
                void (async () => {
                    try {
                        await deleteReaction(existingReaction.reactionId);
                        setAllReactions((prev) => {
                            const next = new Map(prev);
                            const fileReactionsMap = prev.get(fileId);
                            if (fileReactionsMap) {
                                const updatedMap = new Map(fileReactionsMap);
                                const collectionReactions =
                                    updatedMap.get(activeCollectionID) ?? [];
                                updatedMap.set(
                                    activeCollectionID,
                                    collectionReactions.filter(
                                        (r) =>
                                            r.id !==
                                            existingReaction.reactionId,
                                    ),
                                );
                                next.set(fileId, updatedMap);
                            }
                            return next;
                        });
                    } catch (e) {
                        log.error("Failed to delete reaction", e);
                    }
                })();
            } else {
                // Not liked in this collection - add
                void (async () => {
                    try {
                        const collection =
                            await getCollectionByID(activeCollectionID);
                        const reactionId = await addReaction(
                            activeCollectionID,
                            fileId,
                            "green_heart",
                            collection.key,
                        );
                        setAllReactions((prev) => {
                            const next = new Map(prev);
                            const fileReactionsMap = new Map<
                                number,
                                UnifiedReaction[]
                            >(prev.get(fileId) ?? new Map());
                            const collectionReactions =
                                fileReactionsMap.get(activeCollectionID) ?? [];
                            fileReactionsMap.set(activeCollectionID, [
                                ...collectionReactions,
                                {
                                    id: reactionId,
                                    collectionID: activeCollectionID,
                                    fileID: fileId,
                                    reactionType: "green_heart",
                                    userID: user.id,
                                    isDeleted: false,
                                    createdAt: Date.now() * 1000,
                                    updatedAt: Date.now() * 1000,
                                },
                            ]);
                            next.set(fileId, fileReactionsMap);
                            return next;
                        });
                    } catch (e) {
                        log.error("Failed to add reaction", e);
                    }
                })();
            }
        }
    }, [activeCollectionID, getUserFileReactions, user?.id]);

    const handleLikeAlbumSelectorClose = useCallback(
        () => setOpenLikeAlbumSelector(false),
        [],
    );

    const handleToggleAlbumLike = useCallback(
        (albumId: number, isCurrentlyLiked: boolean) => {
            const file = activeAnnotatedFileRef.current?.file;
            if (!file) return;

            const fileId = file.id;

            if (isCurrentlyLiked) {
                // Unlike - delete the reaction
                const reactions = getUserFileReactions(fileId);
                const reactionToDelete = reactions.find(
                    (r) => r.collectionId === albumId,
                );

                if (reactionToDelete) {
                    void (async () => {
                        try {
                            await deleteReaction(reactionToDelete.reactionId);
                            setAllReactions((prev) => {
                                const next = new Map(prev);
                                const fileReactionsMap = prev.get(fileId);
                                if (fileReactionsMap) {
                                    const updatedMap = new Map(
                                        fileReactionsMap,
                                    );
                                    const collectionReactions =
                                        updatedMap.get(albumId) ?? [];
                                    updatedMap.set(
                                        albumId,
                                        collectionReactions.filter(
                                            (r) =>
                                                r.id !==
                                                reactionToDelete.reactionId,
                                        ),
                                    );
                                    next.set(fileId, updatedMap);
                                }
                                return next;
                            });
                        } catch (e) {
                            log.error("Failed to delete reaction", e);
                        }
                    })();
                }
            } else {
                // Like - add a reaction
                void (async () => {
                    try {
                        const collection = await getCollectionByID(albumId);
                        const reactionId = await addReaction(
                            albumId,
                            fileId,
                            "green_heart",
                            collection.key,
                        );
                        setAllReactions((prev) => {
                            const next = new Map(prev);
                            const fileReactionsMap = new Map<
                                number,
                                UnifiedReaction[]
                            >(prev.get(fileId) ?? new Map());
                            const collectionReactions =
                                fileReactionsMap.get(albumId) ?? [];
                            fileReactionsMap.set(albumId, [
                                ...collectionReactions,
                                {
                                    id: reactionId,
                                    collectionID: albumId,
                                    fileID: fileId,
                                    reactionType: "green_heart",
                                    userID: user?.id ?? 0,
                                    isDeleted: false,
                                    createdAt: Date.now() * 1000,
                                    updatedAt: Date.now() * 1000,
                                },
                            ]);
                            next.set(fileId, fileReactionsMap);
                            return next;
                        });
                    } catch (e) {
                        log.error("Failed to add reaction", e);
                    }
                })();
            }
            // Don't close - user might want to toggle more albums
        },
        [getUserFileReactions, user?.id],
    );

    const handleLikeAll = useCallback(() => {
        const file = activeAnnotatedFileRef.current?.file;
        if (!file) return;

        const fileId = file.id;
        const collectionIDs = fileNormalCollectionIDs?.get(fileId) ?? [];
        const existingReactions = getUserFileReactions(fileId);
        const likedCollectionIDs = new Set(
            existingReactions.map((r) => r.collectionId),
        );

        // Filter to only shared collections not already liked
        const collectionsToLike = collectionIDs.filter(
            (id) =>
                !likedCollectionIDs.has(id) &&
                collectionSummaries?.get(id)?.attributes.has("shared"),
        );

        void (async () => {
            try {
                const newReactions: {
                    collectionId: number;
                    reactionId: string;
                }[] = [];
                for (const collectionId of collectionsToLike) {
                    const collection = await getCollectionByID(collectionId);
                    const reactionId = await addReaction(
                        collectionId,
                        fileId,
                        "green_heart",
                        collection.key,
                    );
                    newReactions.push({ collectionId, reactionId });
                }
                setAllReactions((prev) => {
                    const next = new Map(prev);
                    const fileReactionsMap = new Map<number, UnifiedReaction[]>(
                        prev.get(fileId) ?? new Map(),
                    );
                    for (const { collectionId, reactionId } of newReactions) {
                        const collectionReactions =
                            fileReactionsMap.get(collectionId) ?? [];
                        fileReactionsMap.set(collectionId, [
                            ...collectionReactions,
                            {
                                id: reactionId,
                                collectionID: collectionId,
                                fileID: fileId,
                                reactionType: "green_heart",
                                userID: user?.id ?? 0,
                                isDeleted: false,
                                createdAt: Date.now() * 1000,
                                updatedAt: Date.now() * 1000,
                            },
                        ]);
                    }
                    next.set(fileId, fileReactionsMap);
                    return next;
                });
            } catch (e) {
                log.error("Failed to add reactions", e);
            }
        })();
        setOpenLikeAlbumSelector(false);
    }, [
        fileNormalCollectionIDs,
        getUserFileReactions,
        user?.id,
        collectionSummaries,
    ]);

    // Callback invoked when the download action is triggered by activating the
    // download button in the PhotoSwipe bar.
    const handleDownloadBarAction = useCallback(
        (annotatedFile: FileViewerAnnotatedFile) => {
            onDownload!(annotatedFile.file);
        },
        [onDownload],
    );

    // Callback invoked when the download action is triggered by activating the
    // download menu item in the more menu.
    //
    // Not memoized since it uses the frequently changing `activeAnnotatedFile`.
    const handleDownloadMenuAction = () => {
        handleMoreMenuCloseIfNeeded();
        onDownload!(activeAnnotatedFile!.file);
    };

    // Callback invoked when the send link action is triggered by activating the
    // send link menu item in the more menu.
    //
    // Not memoized since it uses the frequently changing `activeAnnotatedFile`.
    const handleSendLinkMenuAction = () => {
        handleMoreMenuCloseIfNeeded();
        onSendLink!(activeAnnotatedFile!.file);
    };

    const handleMore = useCallback(
        (buttonElement: HTMLElement) => setMoreMenuAnchorEl(buttonElement),
        [],
    );

    const handleMoreMenuCloseIfNeeded = useCallback(() => {
        setMoreMenuAnchorEl((el) => {
            if (el) resetMoreMenuButtonOnMenuClose(el);
            return null;
        });
    }, []);

    const handleConfirmDelete = useMemo(() => {
        return onDelete
            ? () => {
                  handleMoreMenuCloseIfNeeded();
                  setOpenConfirmDelete(true);
              }
            : undefined;
    }, [onDelete, handleMoreMenuCloseIfNeeded]);

    const handleConfirmDeleteClose = useCallback(
        () => setOpenConfirmDelete(false),
        [],
    );

    // Not memoized since it uses the frequently changing `activeAnnotatedFile`.
    const handleDelete = async () => {
        const file = activeAnnotatedFile!.file;
        await onDelete!(file);
        handleNeedsRemotePull();
    };

    // Not memoized since it uses the frequently changing `activeAnnotatedFile`.
    const handleCopyImage = useCallback(() => {
        handleMoreMenuCloseIfNeeded();
        if (!activeAnnotatedFile) return;
        const { imageURL } = activeAnnotatedFile.itemData;
        if (!imageURL) return;
        // Safari does not copy if we do not call `navigator.clipboard.write`
        // synchronously within the click event handler, but it does supports
        // passing a promise in lieu of the blob.
        void window.navigator.clipboard
            .write([
                new ClipboardItem({
                    "image/png": createImagePNGBlob(imageURL),
                }),
            ])
            .catch(onGenericError);
    }, [onGenericError, handleMoreMenuCloseIfNeeded, activeAnnotatedFile]);

    const handleAddFileToCollection = useMemo(() => {
        if (!onAddFileToCollection || !activeAnnotatedFile) return undefined;
        return () => {
            handleMoreMenuCloseIfNeeded();
            const sourceSummaryID = fileNormalCollectionIDs
                ?.get(activeAnnotatedFile.file.id)
                ?.find((id) => id === activeCollectionID);
            onAddFileToCollection(activeAnnotatedFile.file, sourceSummaryID);
        };
    }, [
        onAddFileToCollection,
        handleMoreMenuCloseIfNeeded,
        fileNormalCollectionIDs,
        activeAnnotatedFile,
        activeCollectionID,
    ]);

    const handleEditImage = useMemo(() => {
        return onSaveEditedImageCopy
            ? () => {
                  handleMoreMenuCloseIfNeeded();
                  setOpenImageEditor(true);
              }
            : undefined;
    }, [onSaveEditedImageCopy, handleMoreMenuCloseIfNeeded]);

    const handleImageEditorClose = useCallback(
        () => setOpenImageEditor(false),
        [],
    );

    const handleSaveEditedCopy = useMemo(() => {
        return onSaveEditedImageCopy
            ? (
                  editedFile: File,
                  collection: Collection,
                  enteFile: EnteFile,
              ) => {
                  const didStartSave = onSaveEditedImageCopy(
                      editedFile,
                      collection,
                      enteFile,
                  );
                  if (didStartSave) handleClose();
                  return didStartSave;
              }
            : undefined;
    }, [onSaveEditedImageCopy, handleClose]);

    const userID = user?.id;
    const haveUser = userID != undefined;
    const canShowFavorite =
        haveUser &&
        !!favoriteFileIDs &&
        !!pendingFavoriteUpdates &&
        !!onToggleFavorite &&
        !isInTrashSection &&
        !isInHiddenSection;

    const handleAnnotate = useCallback(
        (file: EnteFile, itemData: ItemData): FileViewerAnnotatedFile => {
            const fileID = file.id;
            const isOwnFile = file.ownerID == userID;
            const canFavoriteFile =
                canShowFavorite && (isOwnFile || !!metadataHash(file.metadata));

            const canModify =
                isOwnFile && !isInTrashSection && !isInHiddenSection;

            const showArchive = canModify;

            const showDelete =
                !!handleConfirmDelete &&
                isOwnFile &&
                !isInTrashSection &&
                !isInIncomingSharedCollection;

            const showEditImage =
                !!handleEditImage && canModify && fileIsEditableImage(file);

            const showDownload = (() => {
                if (disableDownload) return undefined;
                if (!onDownload) return undefined;
                if (haveUser) {
                    // Logged in users see the download option in the more menu.
                    return "menu";
                } else {
                    // Guest viewers show download in the bar buttons, in lieu
                    // of the favorite option.
                    return "bar";
                }
            })();

            const showCopyImage = (() => {
                if (disableDownload) return false;
                switch (file.metadata.fileType) {
                    case FileType.image:
                    case FileType.livePhoto:
                        return true;
                    default:
                        return false;
                }
            })();

            const annotation: FileViewerFileAnnotation = {
                fileID,
                isOwnFile,
                showFavorite: canFavoriteFile,
                showDownload,
                showDelete,
                showArchive,
                showCopyImage,
                showEditImage,
            };

            const annotatedFile = { file, annotation, itemData };
            setActiveAnnotatedFile(annotatedFile);
            return annotatedFile;
        },
        [
            userID,
            haveUser,
            disableDownload,
            isInIncomingSharedCollection,
            isInTrashSection,
            isInHiddenSection,
            canShowFavorite,
            onDownload,
            handleEditImage,
            handleConfirmDelete,
        ],
    );

    const handleSelectCollection = useMemo(() => {
        return onSelectCollection
            ? (collectionID: number) => {
                  onSelectCollection(collectionID);
                  handleClose();
              }
            : undefined;
    }, [onSelectCollection, handleClose]);

    const handleSelectPerson = useMemo(() => {
        return onSelectPerson
            ? (personID: string) => {
                  onSelectPerson(personID);
                  handleClose();
              }
            : undefined;
    }, [onSelectPerson, handleClose]);

    // Determine if social buttons (like, comment) should be shown.
    const showSocialButtons = useMemo(() => {
        if (!haveUser) return false;
        if (!enableComment) return false;
        // For logged-in users, check if the comments feature is enabled.
        if (!isCommentsFeatureEnabled) return false;
        // In collection view: check if that specific collection is shared.
        if (
            activeCollectionID &&
            activeCollectionID !== 0 &&
            collectionSummaries
        ) {
            const collectionSummary =
                collectionSummaries.get(activeCollectionID);
            if (collectionSummary?.attributes.has("shared")) return true;
        }
        return false;
    }, [
        haveUser,
        enableComment,
        isCommentsFeatureEnabled,
        activeCollectionID,
        collectionSummaries,
    ]);

    // Check if a file belongs to any shared collection (for gallery view).
    const isFileInSharedCollection = useCallback(
        (fileID: number): boolean => {
            if (!collectionSummaries || !fileNormalCollectionIDs) return false;
            const collectionIDs = fileNormalCollectionIDs.get(fileID) ?? [];
            return collectionIDs.some((collectionID) => {
                const summary = collectionSummaries.get(collectionID);
                return summary?.attributes.has("shared");
            });
        },
        [collectionSummaries, fileNormalCollectionIDs],
    );

    // Delegate callback to check if social buttons should be shown for a file.
    const shouldShowSocialButtons_ = useCallback(
        ({ file }: FileViewerAnnotatedFile): boolean => {
            // If showSocialButtons is already true in collection view, this
            // won't be called. This callback is only for gallery view where we
            // need to check per-file.
            if (!isCommentsFeatureEnabled) return false;
            //
            // If we're in a specific collection context (not gallery view),
            // return false - the collection's shared status is what matters,
            // not whether the file happens to be in some other shared album.
            const isGalleryView =
                !activeCollectionID || activeCollectionID === 0;
            if (!isGalleryView) return false;

            return isFileInSharedCollection(file.id);
        },
        [
            isCommentsFeatureEnabled,
            isFileInSharedCollection,
            activeCollectionID,
        ],
    );

    // Compute shared albums the file belongs to and which are liked for the modal
    const { allAlbumsForFile, likedAlbumIDs } = useMemo(() => {
        const file = activeAnnotatedFile?.file;
        if (!file)
            return { allAlbumsForFile: [], likedAlbumIDs: new Set<number>() };

        // Get all collections the file belongs to, filtered to only shared ones
        const collectionIDs = fileNormalCollectionIDs?.get(file.id) ?? [];
        const allAlbumsForFile = collectionIDs
            .filter((id) =>
                collectionSummaries?.get(id)?.attributes.has("shared"),
            )
            .map((id) => ({
                id,
                name: collectionNameByID?.get(id) ?? `Album ${id}`,
            }));

        // Get the set of liked album IDs from allReactions
        const fileReactionsMap = allReactions.get(file.id);
        const likedAlbumIDs = new Set<number>();

        if (fileReactionsMap) {
            for (const [collectionId, reactions] of fileReactionsMap) {
                const hasUserLike = reactions.some((r) => {
                    if (r.commentID || r.reactionType !== "green_heart")
                        return false;
                    return r.userID === user?.id;
                });
                if (hasUserLike) {
                    likedAlbumIDs.add(collectionId);
                }
            }
        }

        return { allAlbumsForFile, likedAlbumIDs };
    }, [
        activeAnnotatedFile,
        collectionNameByID,
        collectionSummaries,
        fileNormalCollectionIDs,
        allReactions,
        user?.id,
    ]);

    const getFiles = useCallback(() => files, [files]);

    const isFavorite = useCallback(
        ({ file }: FileViewerAnnotatedFile) => {
            if (
                !haveUser ||
                !favoriteFileIDs ||
                !pendingFavoriteUpdates ||
                !onToggleFavorite
            ) {
                return undefined;
            }
            return favoriteFileIDs.has(file.id);
        },
        [haveUser, favoriteFileIDs, pendingFavoriteUpdates, onToggleFavorite],
    );

    const isFavoritePending = useCallback(
        ({ file }: FileViewerAnnotatedFile) =>
            !!pendingFavoriteUpdates?.has(file.id),
        [pendingFavoriteUpdates],
    );

    const toggleFavorite = useCallback(
        ({ file }: FileViewerAnnotatedFile) =>
            onToggleFavorite!(file)
                .catch(onGenericError)
                .finally(handleNeedsRemotePull),
        [onToggleFavorite, onGenericError, handleNeedsRemotePull],
    );

    const isLiked = useCallback(
        ({ file }: FileViewerAnnotatedFile) => {
            const fileReactionsMap = allReactions.get(file.id);
            if (!fileReactionsMap) return false;

            // Check if user has liked this file in any collection
            for (const reactions of fileReactionsMap.values()) {
                const hasUserLike = reactions.some((r) => {
                    if (r.commentID || r.reactionType !== "green_heart")
                        return false;
                    return r.userID === user?.id;
                });
                if (hasUserLike) return true;
            }
            return false;
        },
        [allReactions, user?.id],
    );

    const getCommentCount = useCallback(
        ({ file }: FileViewerAnnotatedFile) => {
            const commentsMap = fileComments.get(file.id);
            if (!commentsMap) return 0;

            const isGalleryView =
                !activeCollectionID || activeCollectionID === 0;
            if (isGalleryView) {
                // Return the count from the collection with most comments
                let maxCount = 0;
                for (const comments of commentsMap.values()) {
                    const count = comments.filter((c) => !c.isDeleted).length;
                    if (count > maxCount) maxCount = count;
                }
                return maxCount;
            } else {
                // Return count from the active collection
                const comments = commentsMap.get(activeCollectionID);
                return comments?.filter((c) => !c.isDeleted).length ?? 0;
            }
        },
        [fileComments, activeCollectionID],
    );

    const updateFullscreenStatus = useCallback(() => {
        setIsFullscreen(!!document.fullscreenElement);
    }, []);

    const handleToggleFullscreen = useCallback(() => {
        handleMoreMenuCloseIfNeeded();
        void (
            document.fullscreenElement
                ? document.exitFullscreen()
                : document.body.requestFullscreen()
        ).then(() => setTimeout(updateFullscreenStatus, 200));
    }, [handleMoreMenuCloseIfNeeded, updateFullscreenStatus]);

    const handleShortcuts = useCallback(() => {
        handleMoreMenuCloseIfNeeded();
        setOpenShortcuts(true);
    }, [handleMoreMenuCloseIfNeeded]);

    const handleShortcutsClose = useCallback(() => setOpenShortcuts(false), []);

    const shouldIgnoreKeyboardEvent = useCallback(
        (event: KeyboardEvent) => {
            // Allow the file info drawer itself to pass through the slide shortcut.
            const shouldAllowFileInfoArrowNavigation =
                openFileInfo &&
                !fileInfoNavigationLocked &&
                !event.shiftKey &&
                !event.metaKey &&
                !event.ctrlKey &&
                event.altKey &&
                (event.key == "ArrowLeft" || event.key == "ArrowRight");

            // Don't handle keydowns if any of the viewer's own modals are open.
            if (
                (openFileInfo && !shouldAllowFileInfoArrowNavigation) ||
                openComments ||
                openLikes ||
                openLikeAlbumSelector ||
                !!moreMenuAnchorEl ||
                openImageEditor ||
                openConfirmDelete ||
                openShortcuts
            ) {
                return true;
            }

            // Also ignore keydowns if keyboard focus is inside an editable field
            // (e.g., when the CollectionSelector dialog's search TextField is focused)
            const activeElement = document.activeElement as HTMLElement | null;
            if (activeElement) {
                const tagName = activeElement.tagName;
                const role = activeElement.getAttribute("role");
                if (
                    tagName === "INPUT" ||
                    tagName === "TEXTAREA" ||
                    tagName === "SELECT" ||
                    activeElement.isContentEditable ||
                    role === "textbox" ||
                    role === "combobox"
                ) {
                    return true;
                }
            }

            return false;
        },
        [
            openFileInfo,
            fileInfoNavigationLocked,
            openComments,
            openLikes,
            openLikeAlbumSelector,
            moreMenuAnchorEl,
            openImageEditor,
            openConfirmDelete,
            openShortcuts,
        ],
    );

    const canCopyImage = useCallback(
        () =>
            activeAnnotatedFile?.annotation.showCopyImage &&
            !!activeAnnotatedFile.itemData.imageURL,
        [activeAnnotatedFile],
    );

    const { isArchived, isPendingToggleArchive, toggleArchived } =
        useMemo(() => {
            let isArchived: boolean | undefined;
            let isPendingToggleArchive: boolean | undefined;
            let toggleArchived: (() => void) | undefined;

            const file = activeAnnotatedFile?.file;

            if (
                pendingVisibilityUpdates &&
                onFileVisibilityUpdate &&
                file &&
                activeAnnotatedFile.annotation.showArchive
            ) {
                switch (file.magicMetadata?.data.visibility) {
                    case undefined:
                    case ItemVisibility.visible:
                        isArchived = false;
                        break;
                    case ItemVisibility.archived:
                        isArchived = true;
                        break;
                }

                isPendingToggleArchive = pendingVisibilityUpdates.has(file.id);

                toggleArchived = () => {
                    handleMoreMenuCloseIfNeeded();
                    void onFileVisibilityUpdate(
                        file,
                        isArchived
                            ? ItemVisibility.visible
                            : ItemVisibility.archived,
                    )
                        .then(handleNeedsRemotePull)
                        .catch(onGenericError);
                };
            }

            return { isArchived, isPendingToggleArchive, toggleArchived };
        }, [
            pendingVisibilityUpdates,
            onFileVisibilityUpdate,
            onGenericError,
            handleNeedsRemotePull,
            handleMoreMenuCloseIfNeeded,
            activeAnnotatedFile,
        ]);

    const performKeyAction = useCallback<
        FileViewerPhotoSwipeDelegate<FileViewerAnnotatedFile>["performKeyAction"]
    >(
        (action) => {
            switch (action) {
                case "delete":
                    if (activeAnnotatedFile?.annotation.showDelete)
                        handleConfirmDelete?.();
                    break;
                case "toggle-archive":
                    if (!isPendingToggleArchive) {
                        // Provide extra visual feedback when the toggle archive
                        // action is invoked via a keyboard shortcut since there
                        // is no corresponding screen control visible (the more
                        // menu might not be visible).
                        onVisualFeedback();
                        toggleArchived?.();
                    }
                    break;
                case "copy":
                    if (canCopyImage()) handleCopyImage();
                    break;
                case "toggle-fullscreen":
                    handleToggleFullscreen();
                    break;
                case "help":
                    handleShortcuts();
                    break;
            }
        },
        [
            onVisualFeedback,
            handleConfirmDelete,
            handleCopyImage,
            handleToggleFullscreen,
            handleShortcuts,
            activeAnnotatedFile,
            isPendingToggleArchive,
            toggleArchived,
            canCopyImage,
        ],
    );

    // Initial value of delegate.
    if (!delegateRef.current) {
        delegateRef.current = {
            getFiles,
            isFavorite,
            isFavoritePending,
            toggleFavorite,
            isLiked,
            getCommentCount,
            shouldShowSocialButtons: shouldShowSocialButtons_,
            shouldIgnoreKeyboardEvent,
            performKeyAction,
        };
    }

    // Updates to delegate callbacks.
    useEffect(() => {
        const delegate = delegateRef.current!;
        delegate.getFiles = getFiles;
        delegate.isFavorite = isFavorite;
        delegate.isFavoritePending = isFavoritePending;
        delegate.toggleFavorite = toggleFavorite;
        delegate.isLiked = isLiked;
        delegate.getCommentCount = getCommentCount;
        delegate.shouldShowSocialButtons = shouldShowSocialButtons_;
        delegate.shouldIgnoreKeyboardEvent = shouldIgnoreKeyboardEvent;
        delegate.performKeyAction = performKeyAction;
    }, [
        getFiles,
        isFavorite,
        isFavoritePending,
        toggleFavorite,
        isLiked,
        getCommentCount,
        shouldShowSocialButtons_,
        shouldIgnoreKeyboardEvent,
        performKeyAction,
    ]);

    // Handle updates to files.
    //
    // See: [Note: Updates to the files prop for FileViewer]
    useEffect(() => {
        if (!files.length) {
            // If there are no more files left, close the viewer.
            handleClose();
        } else if (open && activeAnnotatedFile) {
            // Only refresh if the viewer is still open and we have an active file.
            // This prevents race conditions when navigating away (e.g., when clicking
            // the navigate button in AlbumAddedNotification while the viewer is open).
            psRef.current?.refreshSlideOnFilesUpdateIfNeeded();
        }
    }, [handleClose, files, open, activeAnnotatedFile]);

    useEffect(() => {
        // This effect might get triggered when the none of the files that were
        // being shown are eligible to be shown anymore. e.g. suppose we are the
        // archiveItems pseudo-collection, and the only archived file there is
        // marked as unarchived by the user within the file viewer.
        //
        // In such cases, don't attempt to refresh since that causes various
        // invariants (like the existence of a "currentFile") to get broken
        // inside the `FileViewerPhotoSwipe` implementation.
        if (open && files.length) {
            psRef.current?.refreshCurrentSlideFavoriteButtonIfNeeded();
        }
    }, [favoriteFileIDs, pendingFavoriteUpdates, files, open]);

    // Refresh like button when allReactions changes.
    useEffect(() => {
        if (open && files.length) {
            psRef.current?.refreshCurrentSlideLikeButtonIfNeeded();
        }
    }, [allReactions, files, open]);

    // Fetch comments and reactions for the current file (only for shared albums).
    const activeFileID = activeAnnotatedFile?.file.id;
    useEffect(() => {
        if (!open || !activeFileID) return;

        // Only fetch social data if social buttons should be shown.
        // In collection view, use showSocialButtons (based on that collection).
        // In gallery view, check if the file is in any shared collection.
        const isGalleryView = !activeCollectionID || activeCollectionID === 0;
        const shouldFetch =
            showSocialButtons ||
            (isCommentsFeatureEnabled &&
                isGalleryView &&
                isFileInSharedCollection(activeFileID));
        if (!shouldFetch) return;

        void (async () => {
            try {
                const commentsMap = new Map<number, Comment[]>();
                const reactionsMap = new Map<number, UnifiedReaction[]>();
                const newUserIDToEmail = new Map<number, string>();
                const newAnonUserNames = new Map<string, string>();

                const collectionIDs = isGalleryView
                    ? (fileNormalCollectionIDs?.get(activeFileID) ?? [])
                    : [activeCollectionID];

                for (const collectionId of collectionIDs) {
                    try {
                        const collection =
                            await getCollectionByID(collectionId);

                        // Cache collection data for polling refresh
                        collectionCacheRef.current.set(collectionId, {
                            key: collection.key,
                            ownerID: collection.owner.id,
                            ownerEmail: collection.owner.email,
                            sharees: collection.sharees.map((s) => ({
                                id: s.id,
                                email: s.email,
                            })),
                            hasPublicURLs: collection.publicURLs.length > 0,
                        });

                        // Build user ID to email map from collection owner and sharees
                        if (collection.owner.email) {
                            newUserIDToEmail.set(
                                collection.owner.id,
                                collection.owner.email,
                            );
                        }
                        for (const sharee of collection.sharees) {
                            if (sharee.email) {
                                newUserIDToEmail.set(sharee.id, sharee.email);
                            }
                        }

                        const { comments, reactions } =
                            await getUnifiedSocialDiff(
                                collectionId,
                                activeFileID,
                                collection.key,
                            );

                        commentsMap.set(collectionId, comments);
                        reactionsMap.set(collectionId, reactions);

                        // Fetch anonymous user profiles only if collection has public links
                        if (collection.publicURLs.length > 0) {
                            try {
                                const anonProfiles = await getAnonProfiles(
                                    collectionId,
                                    collection.key,
                                );
                                for (const [
                                    anonUserID,
                                    userName,
                                ] of anonProfiles) {
                                    newAnonUserNames.set(anonUserID, userName);
                                }
                            } catch {
                                // Ignore anon profiles fetch failures
                            }
                        }
                    } catch {
                        // Skip collections that fail to fetch
                    }
                }

                setFileComments((prev) => {
                    const next = new Map(prev);
                    next.set(activeFileID, commentsMap);
                    return next;
                });

                setAllReactions((prev) => {
                    const next = new Map(prev);
                    next.set(activeFileID, reactionsMap);
                    return next;
                });

                setUserIDToEmail((prev) => {
                    const next = new Map(prev);
                    for (const [id, email] of newUserIDToEmail) {
                        next.set(id, email);
                    }
                    return next;
                });

                setAnonUserNames((prev) => {
                    const next = new Map(prev);
                    for (const [id, name] of newAnonUserNames) {
                        next.set(id, name);
                    }
                    return next;
                });
            } catch (e) {
                log.error("Failed to fetch social data", e);
                setFileComments((prev) => {
                    const next = new Map(prev);
                    next.delete(activeFileID);
                    return next;
                });
                setAllReactions((prev) => {
                    const next = new Map(prev);
                    next.delete(activeFileID);
                    return next;
                });
            }
        })();
    }, [
        open,
        activeFileID,
        activeCollectionID,
        fileNormalCollectionIDs,
        showSocialButtons,
        isFileInSharedCollection,
        isCommentsFeatureEnabled,
    ]);

    // Refresh comment count when fileComments changes.
    useEffect(() => {
        if (open && files.length) {
            psRef.current?.refreshCurrentSlideCommentCountIfNeeded();
        }
    }, [fileComments, files, open]);

    // Polling interval for refreshing social data (5 seconds)
    const SOCIAL_REFRESH_INTERVAL_MS = 5_000;

    // Refresh social data for logged-in users (uses cached collection keys)
    const refreshSocialData = useCallback(async () => {
        if (!activeFileID) return;

        const isGalleryView = !activeCollectionID || activeCollectionID === 0;
        const shouldFetch =
            showSocialButtons ||
            (isCommentsFeatureEnabled &&
                isGalleryView &&
                isFileInSharedCollection(activeFileID));
        if (!shouldFetch) return;

        try {
            const commentsMap = new Map<number, Comment[]>();
            const reactionsMap = new Map<number, UnifiedReaction[]>();
            const newAnonUserNames = new Map<string, string>();

            const collectionIDs = isGalleryView
                ? (fileNormalCollectionIDs?.get(activeFileID) ?? [])
                : [activeCollectionID];

            for (const collectionId of collectionIDs) {
                // Use cached collection data (populated during initial fetch)
                const cached = collectionCacheRef.current.get(collectionId);
                if (!cached) continue; // Skip if not in cache

                try {
                    const { comments, reactions } = await getUnifiedSocialDiff(
                        collectionId,
                        activeFileID,
                        cached.key,
                    );

                    commentsMap.set(collectionId, comments);
                    reactionsMap.set(collectionId, reactions);

                    if (cached.hasPublicURLs) {
                        try {
                            const anonProfiles = await getAnonProfiles(
                                collectionId,
                                cached.key,
                            );
                            for (const [anonUserID, userName] of anonProfiles) {
                                newAnonUserNames.set(anonUserID, userName);
                            }
                        } catch {
                            // Ignore
                        }
                    }
                } catch {
                    // Skip failed collections
                }
            }

            setFileComments((prev) => {
                const next = new Map(prev);
                next.set(activeFileID, commentsMap);
                return next;
            });

            setAllReactions((prev) => {
                const next = new Map(prev);
                next.set(activeFileID, reactionsMap);
                return next;
            });

            setAnonUserNames((prev) => {
                const next = new Map(prev);
                for (const [id, name] of newAnonUserNames) {
                    next.set(id, name);
                }
                return next;
            });
        } catch (e) {
            log.error("Failed to refresh social data", e);
        }
    }, [
        activeFileID,
        activeCollectionID,
        fileNormalCollectionIDs,
        showSocialButtons,
        isFileInSharedCollection,
        isCommentsFeatureEnabled,
    ]);

    // Poll for social data when comments or likes sidebar is open.
    useInterval(
        refreshSocialData,
        openComments || openLikes ? SOCIAL_REFRESH_INTERVAL_MS : null,
    );

    useEffect(() => {
        if (open) {
            // We're open. Create psRef. This will show the file viewer dialog.
            log.debug(() => "Opening file viewer");

            const pswp = new FileViewerPhotoSwipe({
                initialIndex,
                haveUser,
                showSocialButtons,
                enableComment,
                showFullscreenButton,
                disableEscapeClose,
                delegate: delegateRef.current!,
                onClose: () => {
                    if (psRef.current) handleClose();
                },
                onAnnotate: handleAnnotate,
                onViewInfo: handleViewInfo,
                onViewComments: handleViewComments,
                onViewLikes: handleViewLikes,
                onLikeClick: handleLikeClick,
                onDownload: handleDownloadBarAction,
                onMore: handleMore,
            });

            psRef.current = pswp;

            return () => {
                // Close dialog in the effect callback.
                log.debug(() => "Closing file viewer");
                pswp.closeIfNeeded();
            };
        } else {
            return undefined;
        }
        // Be careful with adding new dependencies here, or changing the source
        // of existing ones. If any of these dependencies change unnecessarily,
        // then the file viewer will start getting reloaded even when it is
        // already open.
        //
        // Note: showSocialButtons and enableComment are intentionally NOT included
        // here even though they're passed to the constructor. The delegate's
        // shouldShowSocialButtons handles dynamic visibility, and these values only
        // change based on collectionSummaries which we don't want to trigger a full
        // recreation.
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [
        open,
        onClose,
        user,
        initialIndex,
        disableDownload,
        showFullscreenButton,
        disableEscapeClose,
        haveUser,
        handleClose,
        handleAnnotate,
        handleViewInfo,
        handleViewComments,
        handleViewLikes,
        handleLikeClick,
        handleDownloadBarAction,
        handleMore,
    ]);

    useEffect(() => {
        if (!open || !shouldCloseOnBrowserBack) return;

        // Consume one browser-back action to close the viewer overlay instead
        // of navigating away immediately.
        const stateMarker = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
        browserBackStateRef.current = stateMarker;

        const currentState: unknown = window.history.state;
        const viewerState = addFileViewerBackStateMarker(
            currentState,
            stateMarker,
        );
        window.history.pushState(viewerState, "", window.location.href);

        const handlePopState = () => {
            if (browserBackStateRef.current != stateMarker) return;
            browserBackStateRef.current = undefined;
            handleCloseRef.current();
        };

        window.addEventListener("popstate", handlePopState);

        return () => {
            window.removeEventListener("popstate", handlePopState);
            if (browserBackStateRef.current != stateMarker) return;
            browserBackStateRef.current = undefined;

            const latestHistoryState: unknown = window.history.state;
            if (hasFileViewerBackStateMarker(latestHistoryState, stateMarker)) {
                window.history.back();
            }
        };
    }, [open, shouldCloseOnBrowserBack]);

    const handleFileMetadataUpdate = useMemo(() => {
        return onRemoteFilesPull
            ? async () => {
                  // Wait for the files pull to complete.
                  await onRemoteFilesPull();
                  // Set the flag to trigger the full pull later.
                  handleNeedsRemotePull();
              }
            : undefined;
    }, [onRemoteFilesPull, handleNeedsRemotePull]);

    const handleUpdateCaption = useCallback(
        (fileID: number, newCaption: string) => {
            updateItemDataAlt(fileID, newCaption);
            psRef.current!.refreshCurrentSlideContent();
        },
        [],
    );

    useEffect(updateFullscreenStatus, [updateFullscreenStatus]);

    if (!activeAnnotatedFile) {
        return <></>;
    }

    return (
        <>
            <FileInfo
                open={openFileInfo}
                onClose={handleFileInfoClose}
                file={activeAnnotatedFile.file}
                exif={activeFileExif}
                allowEdits={activeAnnotatedFile.annotation.isOwnFile}
                allowMap={haveUser}
                showCollections={haveUser}
                fileCollectionIDs={fileCollectionIDs ?? fileNormalCollectionIDs}
                hiddenCollectionIDs={hiddenCollectionIDs}
                onFileMetadataUpdate={handleFileMetadataUpdate}
                onUpdateCaption={handleUpdateCaption}
                onSelectCollection={handleSelectCollection}
                onSelectPerson={handleSelectPerson}
                onNavigationLockChange={setFileInfoNavigationLocked}
                {...{ collectionNameByID }}
            />
            <CommentsSidebar
                open={openComments}
                onClose={handleCommentsClose}
                file={activeAnnotatedFile.file}
                activeCollectionID={activeCollectionID}
                fileNormalCollectionIDs={fileNormalCollectionIDs}
                collectionSummaries={collectionSummaries}
                currentUserID={user?.id}
                prefetchedComments={fileComments.get(
                    activeAnnotatedFile.file.id,
                )}
                prefetchedReactions={allReactions.get(
                    activeAnnotatedFile.file.id,
                )}
                prefetchedUserIDToEmail={userIDToEmail}
                onCommentAdded={handleCommentAdded}
                onCommentDeleted={handleCommentDeleted}
                onCommentReactionAdded={handleCommentReactionAdded}
                onCommentReactionDeleted={handleCommentReactionDeleted}
                highlightCommentID={highlightCommentID}
                anonUserNames={anonUserNames}
            />
            <LikesSidebar
                open={openLikes}
                onClose={handleLikesClose}
                file={activeAnnotatedFile.file}
                activeCollectionID={activeCollectionID}
                fileNormalCollectionIDs={fileNormalCollectionIDs}
                collectionSummaries={collectionSummaries}
                currentUserID={user?.id}
                prefetchedReactions={allReactions.get(
                    activeAnnotatedFile.file.id,
                )}
                prefetchedUserIDToEmail={userIDToEmail}
                anonUserNames={anonUserNames}
            />
            <LikeAlbumSelectorModal
                open={openLikeAlbumSelector}
                onClose={handleLikeAlbumSelectorClose}
                albums={allAlbumsForFile}
                likedAlbumIDs={likedAlbumIDs}
                onToggleAlbum={handleToggleAlbumLike}
                onLikeAll={handleLikeAll}
            />
            <MoreMenu
                open={!!moreMenuAnchorEl}
                onClose={handleMoreMenuCloseIfNeeded}
                anchorEl={moreMenuAnchorEl}
                id={moreMenuID}
                disableAutoFocusItem
                slotProps={{ list: { "aria-labelledby": moreButtonID } }}
            >
                {activeAnnotatedFile.annotation.showDownload == "menu" && (
                    <MoreMenuItem onClick={handleDownloadMenuAction}>
                        <MoreMenuItemTitle>{t("download")}</MoreMenuItemTitle>
                        <FileDownloadOutlinedIcon />
                    </MoreMenuItem>
                )}
                {activeAnnotatedFile.annotation.isOwnFile &&
                    !isInTrashSection &&
                    onSendLink && (
                        <MoreMenuItem onClick={handleSendLinkMenuAction}>
                            <MoreMenuItemTitle>Send link</MoreMenuItemTitle>
                            <HugeiconsIcon icon={Navigation03Icon} size={20} />
                        </MoreMenuItem>
                    )}
                {activeAnnotatedFile.annotation.showDelete && (
                    <MoreMenuItem onClick={handleConfirmDelete}>
                        <MoreMenuItemTitle>{t("delete")}</MoreMenuItemTitle>
                        <DeleteIcon />
                    </MoreMenuItem>
                )}
                {isArchived !== undefined && (
                    <MoreMenuItem
                        onClick={toggleArchived}
                        disabled={isPendingToggleArchive}
                    >
                        <MoreMenuItemTitle>
                            {isArchived ? t("unarchive") : t("archive")}
                        </MoreMenuItemTitle>
                        {isArchived ? (
                            <UnArchiveIcon />
                        ) : (
                            <ArchiveOutlinedIcon />
                        )}
                    </MoreMenuItem>
                )}
                {handleAddFileToCollection &&
                    !(isInTrashSection || isInHiddenSection) && (
                        <MoreMenuItem onClick={handleAddFileToCollection}>
                            <MoreMenuItemTitle>
                                {t("add_to_album")}
                            </MoreMenuItemTitle>
                            <AddIcon />
                        </MoreMenuItem>
                    )}
                {canCopyImage() && (
                    <MoreMenuItem onClick={handleCopyImage}>
                        <MoreMenuItemTitle>
                            {t("copy_as_png")}
                        </MoreMenuItemTitle>
                        {/* Tweak icon size to visually fit better with neighbours */}
                        <ContentCopyIcon sx={{ "&&": { fontSize: "18px" } }} />
                    </MoreMenuItem>
                )}

                {activeAnnotatedFile.annotation.showEditImage && (
                    <MoreMenuItem onClick={handleEditImage}>
                        <MoreMenuItemTitle>{t("edit_image")}</MoreMenuItemTitle>
                        <EditIcon />
                    </MoreMenuItem>
                )}
                <MoreMenuItem
                    onClick={handleToggleFullscreen}
                    divider
                    sx={{
                        borderColor: "fixed.dark.divider",
                        /* 12px + 2px */
                        pb: "14px",
                    }}
                >
                    <MoreMenuItemTitle>
                        {isFullscreen
                            ? t("exit_fullscreen")
                            : t("go_fullscreen")}
                    </MoreMenuItemTitle>
                    {isFullscreen ? (
                        <FullscreenExitOutlinedIcon />
                    ) : (
                        <FullscreenOutlinedIcon />
                    )}
                </MoreMenuItem>
                <MoreMenuItem onClick={handleShortcuts} sx={{ mt: "2px" }}>
                    <Typography sx={{ color: "fixed.dark.text.faint" }}>
                        {t("shortcuts")}
                    </Typography>
                </MoreMenuItem>
            </MoreMenu>
            <ConfirmDeleteFileDialog
                open={openConfirmDelete}
                onClose={handleConfirmDeleteClose}
                onConfirm={handleDelete}
            />
            {handleSaveEditedCopy && (
                <ImageEditorOverlay
                    open={openImageEditor}
                    onClose={handleImageEditorClose}
                    file={activeAnnotatedFile.file}
                    onSaveEditedCopy={handleSaveEditedCopy}
                />
            )}
            <Shortcuts
                open={openShortcuts}
                onClose={handleShortcutsClose}
                {...{ disableDownload, haveUser }}
            />
        </>
    );
};

const MoreMenu = styled(Menu)(
    ({ theme }) => `
    & .MuiPaper-root {
        background-color: ${theme.vars.palette.fixed.dark.background.paper};
    }
    & .MuiList-root {
        padding-block: 2px;
    }
`,
);

const MoreMenuItem = styled(MenuItem)(
    ({ theme }) => `
    min-width: 210px;

    /* MUI MenuItem default implementation has a minHeight of "48px" below the
       "sm" breakpoint, and auto after it. We always want the same height, so
       set minHeight auto and use an explicit padding always to come out to 44px
       (20px (icon or Typography height + 12 + 12) */
    padding-block: 12px;
    min-height: auto;

    gap: 1;
    justify-content: space-between;
    align-items: center;

    /* Same as other controls on the PhotoSwipe UI */
    color: rgba(255 255 255 / 0.85);
    &:hover {
        color: rgba(255 255 255 / 1);
        background-color: ${theme.vars.palette.fixed.dark.background.paper2}
    }

    .MuiSvgIcon-root {
        font-size: 20px;
    }
`,
);

const MoreMenuItemTitle: React.FC<React.PropsWithChildren> = ({ children }) => (
    <Typography sx={{ fontWeight: "medium" }}>{children}</Typography>
);

type ConfirmDeleteFileDialogProps = ModalVisibilityProps & {
    /**
     * Called when the user confirms the deletion.
     *
     * The delete button will show an activity indicator until this async
     * operation completes.
     */
    onConfirm: () => Promise<void>;
};

/**
 * A bespoke variant of AttributedMiniDialog for use by the delete file
 * confirmation prompt that we show in the file viewer.
 *
 * - It auto focuses the primary action.
 * - It uses a lighter backdrop in light mode.
 */
const ConfirmDeleteFileDialog: React.FC<ConfirmDeleteFileDialogProps> = ({
    open,
    onClose,
    onConfirm,
}) => {
    const [phase, setPhase] = useState<"loading" | "failed" | undefined>();

    const resetPhaseAndClose = () => {
        setPhase(undefined);
        onClose();
    };

    const handleClick = async () => {
        setPhase("loading");
        try {
            await onConfirm();
            resetPhaseAndClose();
        } catch (e) {
            log.error(e);
            setPhase("failed");
        }
    };

    const handleClose: ModalProps["onClose"] = (_, reason) => {
        // Ignore backdrop clicks when we're processing the user request.
        if (reason == "backdropClick" && phase == "loading") return;
        resetPhaseAndClose();
    };

    return (
        <TitledMiniDialog
            open={open}
            onClose={handleClose}
            title={t("trash_file_title")}
            sx={(theme) => ({
                // See: [Note: Lighter backdrop for overlays on photo viewer]
                ...theme.applyStyles("light", {
                    ".MuiBackdrop-root": {
                        backgroundColor: theme.vars.palette.backdrop.faint,
                    },
                }),
            })}
        >
            <Typography sx={{ color: "text.muted" }}>
                {t("trash_file_message")}
            </Typography>
            <Stack sx={{ pt: 3, gap: 1 }}>
                {phase == "failed" && <InlineErrorIndicator />}
                <LoadingButton
                    loading={phase == "loading"}
                    fullWidth
                    color="critical"
                    autoFocus
                    onClick={handleClick}
                >
                    {t("move_to_trash")}
                </LoadingButton>
                <FocusVisibleButton
                    fullWidth
                    color="secondary"
                    disabled={phase == "loading"}
                    onClick={resetPhaseAndClose}
                >
                    {t("cancel")}
                </FocusVisibleButton>
            </Stack>
        </TitledMiniDialog>
    );
};

type ShortcutsProps = ModalVisibilityProps &
    Pick<FileViewerProps, "disableDownload"> & {
        /**
         * `true` if we're running in a context where there is a logged in user.
         */
        haveUser: boolean;
    };

const Shortcuts: React.FC<ShortcutsProps> = ({
    open,
    onClose,
    disableDownload,
    haveUser,
}) => (
    <Dialog
        {...{ open, onClose }}
        fullWidth
        fullScreen={useIsSmallWidth()}
        slotProps={{ backdrop: { sx: { backdropFilter: "blur(30px)" } } }}
    >
        <SpacedRow sx={{ pt: 2, px: 2.5 }}>
            <DialogTitle>{t("shortcuts")}</DialogTitle>
            <DialogCloseIconButton {...{ onClose }} />
        </SpacedRow>
        <ShortcutsContent>
            <Shortcut action={t("close")} shortcut={ut("Esc")} />
            <Shortcut
                action={formattedListJoin([t("previous"), t("next")])}
                shortcut={`${formattedListJoin([ut("←"), ut("→")])} ${ut("(Option/Alt)")}`}
            />
            <Shortcut
                action={t("video_seek")}
                shortcut={formattedListJoin([ut("←"), ut("→")])}
            />
            <Shortcut
                action={t("zoom")}
                shortcut={formattedListJoin([t("mouse_scroll"), t("pinch")])}
            />
            <Shortcut
                action={t("zoom_preset")}
                shortcut={formattedListJoin([ut("Z"), t("tap_inside_image")])}
            />
            <Shortcut
                action={t("toggle_controls")}
                shortcut={formattedListJoin([ut("H"), t("tap_outside_image")])}
            />
            <Shortcut
                action={t("pan")}
                shortcut={formattedListJoin([ut("W A S D"), t("drag")])}
            />
            <Shortcut
                action={formattedListJoin([t("play"), t("pause")])}
                shortcut={ut("Space")}
            />
            <Shortcut action={t("toggle_live")} shortcut={ut("Space")} />
            <Shortcut action={t("toggle_audio")} shortcut={ut("M")} />
            {haveUser && (
                <Shortcut action={t("toggle_favorite")} shortcut={ut("L")} />
            )}
            <Shortcut action={t("view_info")} shortcut={ut("I")} />
            {!disableDownload && (
                <Shortcut action={t("download")} shortcut={ut("K")} />
            )}
            {haveUser && (
                <Shortcut
                    action={t("delete")}
                    shortcut={formattedListJoin([
                        ut("Delete"),
                        ut("Backspace"),
                    ])}
                />
            )}
            {haveUser && (
                <Shortcut action={t("toggle_archive")} shortcut={ut("X")} />
            )}
            {!disableDownload && (
                <Shortcut action={t("copy_as_png")} shortcut={ut("^C / ⌘C")} />
            )}
            <Shortcut action={t("toggle_fullscreen")} shortcut={ut("F")} />
            <Shortcut action={t("show_shortcuts")} shortcut={ut("?")} />
        </ShortcutsContent>
    </Dialog>
);

const ShortcutsContent: React.FC<React.PropsWithChildren> = ({ children }) => (
    <DialogContent sx={{ "&&": { pt: 1, pb: 5, px: 5 } }}>
        <ShortcutsTable>
            <tbody>{children}</tbody>
        </ShortcutsTable>
    </DialogContent>
);

const ShortcutsTable = styled("table")`
    border-collapse: separate;
    border-spacing: 0 14px;
`;

interface ShortcutProps {
    action: string;
    shortcut: string;
}

const Shortcut: React.FC<ShortcutProps> = ({ action, shortcut }) => (
    <tr>
        <Typography
            component="td"
            sx={{ color: "text.muted", width: "min(20ch, 40svw)" }}
        >
            {action}
        </Typography>

        <Typography component="td" sx={{ fontWeight: "medium" }}>
            {shortcut}
        </Typography>
    </tr>
);

const fileIsEditableImage = (file: EnteFile) => {
    // Only images are editable.
    if (file.metadata.fileType !== FileType.image) return false;

    const extension = lowercaseExtension(fileFileName(file));
    // Assume it is editable;
    let isRenderable = true;
    if (extension && needsJPEGConversion(extension)) {
        // See if the file is on the whitelist of extensions that we know
        // will not be directly renderable.
        if (!isDesktop) {
            // On the web, we only support HEIC conversion.
            isRenderable = isHEICExtension(extension);
        }
    }
    return isRenderable;
};

/**
 * Return a promise that resolves with a "image/png" blob derived from the given
 * {@link imageURL} that can be written to the navigator's clipboard.
 */
const createImagePNGBlob = async (imageURL: string): Promise<Blob> =>
    new Promise((resolve, reject) => {
        const image = new Image();
        image.onload = () => {
            const canvas = document.createElement("canvas");
            canvas.width = image.width;
            canvas.height = image.height;
            canvas.getContext("2d")!.drawImage(image, 0, 0);
            canvas.toBlob(
                (blob) =>
                    blob ? resolve(blob) : reject(new Error("toBlob failed")),
                "image/png",
            );
        };
        image.onerror = reject;
        image.src = imageURL;
    });
