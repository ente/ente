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

export interface FileViewerFileAnnotation {
    fileID: number;
    isOwnFile: boolean;
    showFavorite: boolean;
    showDownload: "bar" | "menu" | undefined;
    showDelete: boolean;
    showArchive: boolean;
    showCopyImage: boolean;
    showEditImage: boolean;
}

export interface FileViewerAnnotatedFile {
    file: EnteFile;
    annotation: FileViewerFileAnnotation;
    itemData: ItemData;
}

export type FileViewerInitialSidebar = "likes" | "comments";

export type FileViewerProps = ModalVisibilityProps & {
    user?: LocalUser;
    files: EnteFile[];
    initialIndex: number;
    initialSidebar?: FileViewerInitialSidebar;
    highlightCommentID?: string;
    disableDownload?: boolean;
    showFullscreenButton?: boolean;
    isInIncomingSharedCollection?: boolean;
    isInTrashSection?: boolean;
    isInHiddenSection?: boolean;
    favoriteFileIDs?: Set<number>;
    pendingFavoriteUpdates?: Set<number>;
    pendingVisibilityUpdates?: Set<number>;
    fileNormalCollectionIDs?: FileInfoProps["fileCollectionIDs"];
    fileCollectionIDs?: FileInfoProps["fileCollectionIDs"];
    hiddenCollectionIDs?: FileInfoProps["hiddenCollectionIDs"];
    collectionSummaries?: CollectionSummaries;
    onTriggerRemotePull?: () => void;
    onRemoteFilesPull?: () => Promise<void>;
    onVisualFeedback: () => void;
    onToggleFavorite?: (file: EnteFile) => Promise<void>;
    onFileVisibilityUpdate?: (
        file: EnteFile,
        visibility: ItemVisibility,
    ) => Promise<void>;
    onDownload?: (file: EnteFile) => void;
    onSendLink?: (file: EnteFile) => void;
    onDelete?: (file: EnteFile) => Promise<void>;
    onSaveEditedImageCopy?: ImageEditorOverlayProps["onSaveEditedCopy"];

    onAddFileToCollection?: (
        file: EnteFile,
        sourceCollectionSummaryID?: number,
    ) => void;
    activeCollectionID?: number;
    shouldCloseOnBrowserBack?: boolean;
    disableEscapeClose?: boolean;
    enableComment?: boolean;
    isCommentsFeatureEnabled?: boolean;
} & Pick<
        FileInfoProps,
        "collectionNameByID" | "onSelectCollection" | "onSelectPerson"
    >;

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

    // Keep this identity stable so dynamic props do not recreate PhotoSwipe.
    const delegateRef = useRef<
        FileViewerPhotoSwipeDelegate<FileViewerAnnotatedFile> | undefined
    >(undefined);

    const psRef = useRef<
        FileViewerPhotoSwipe<FileViewerAnnotatedFile> | undefined
    >(undefined);
    const handleCloseRef = useRef<() => void>(() => undefined);
    const browserBackStateRef = useRef<string | undefined>(undefined);

    // This is the file from the last PhotoSwipe callback, not necessarily its current slide.
    const [activeAnnotatedFile, setActiveAnnotatedFile] = useState<
        FileViewerAnnotatedFile | undefined
    >(undefined);

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

    const [fileComments, setFileComments] = useState<
        Map<number, Map<number, Comment[]>>
    >(new Map());

    const [allReactions, setAllReactions] = useState<
        Map<number, Map<number, UnifiedReaction[]>>
    >(new Map());

    const [userIDToEmail, setUserIDToEmail] = useState<Map<number, string>>(
        new Map(),
    );

    const [anonUserNames, setAnonUserNames] = useState<Map<string, string>>(
        new Map(),
    );

    const fileCommentsRef = useRef(fileComments);
    useEffect(() => {
        fileCommentsRef.current = fileComments;
    }, [fileComments]);

    const allReactionsRef = useRef(allReactions);
    useEffect(() => {
        allReactionsRef.current = allReactions;
    }, [allReactions]);

    const collectionSummariesRef = useRef(collectionSummaries);
    useEffect(() => {
        collectionSummariesRef.current = collectionSummaries;
    }, [collectionSummaries]);

    const fileNormalCollectionIDsRef = useRef(fileNormalCollectionIDs);
    useEffect(() => {
        fileNormalCollectionIDsRef.current = fileNormalCollectionIDs;
    }, [fileNormalCollectionIDs]);

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

    const hasOpenedInitialSidebarRef = useRef(false);

    useEffect(() => {
        if (open && initialSidebar && !hasOpenedInitialSidebarRef.current) {
            hasOpenedInitialSidebarRef.current = true;
            if (initialSidebar === "comments") {
                setOpenComments(true);
            } else {
                setOpenLikes(true);
            }
        }
        if (!open) {
            hasOpenedInitialSidebarRef.current = false;
        }
    }, [open, initialSidebar]);

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
        setMoreMenuAnchorEl(null);
        setOpenImageEditor(false);
        setOpenConfirmDelete(false);
        setOpenShortcuts(false);
        setIsFullscreen(false);
        onClose();
    }, [onTriggerRemotePull, onClose]);

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

    const activeAnnotatedFileRef = useRef(activeAnnotatedFile);
    activeAnnotatedFileRef.current = activeAnnotatedFile;

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
            const allCollectionIDs =
                fileNormalCollectionIDsRef.current?.get(fileId) ?? [];
            const collectionIDs = allCollectionIDs.filter((id) =>
                collectionSummariesRef.current
                    ?.get(id)
                    ?.attributes.has("shared"),
            );

            if (reactions.length === 0) {
                if (collectionIDs.length === 1) {
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
                    setOpenLikeAlbumSelector(true);
                }
            } else {
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
            const existingReaction = reactions.find(
                (r) => r.collectionId === activeCollectionID,
            );

            if (existingReaction) {
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

    const handleDownloadBarAction = useCallback(
        (annotatedFile: FileViewerAnnotatedFile) => {
            onDownload!(annotatedFile.file);
        },
        [onDownload],
    );

    const handleDownloadMenuAction = () => {
        handleMoreMenuCloseIfNeeded();
        onDownload!(activeAnnotatedFile!.file);
    };

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

    const handleDelete = async () => {
        const file = activeAnnotatedFile!.file;
        await onDelete!(file);
        handleNeedsRemotePull();
    };

    const handleCopyImage = useCallback(() => {
        handleMoreMenuCloseIfNeeded();
        if (!activeAnnotatedFile) return;
        const { imageURL } = activeAnnotatedFile.itemData;
        if (!imageURL) return;
        // Safari requires clipboard.write to run synchronously in the click handler.
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
                    return "menu";
                } else {
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

    const showSocialButtons = useMemo(() => {
        if (!haveUser) return false;
        if (!enableComment) return false;
        if (!isCommentsFeatureEnabled) return false;
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

    const shouldShowSocialButtons_ = useCallback(
        ({ file }: FileViewerAnnotatedFile): boolean => {
            if (!isCommentsFeatureEnabled) return false;
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

    const { allAlbumsForFile, likedAlbumIDs } = useMemo(() => {
        const file = activeAnnotatedFile?.file;
        if (!file)
            return { allAlbumsForFile: [], likedAlbumIDs: new Set<number>() };

        const collectionIDs = fileNormalCollectionIDs?.get(file.id) ?? [];
        const allAlbumsForFile = collectionIDs
            .filter((id) =>
                collectionSummaries?.get(id)?.attributes.has("shared"),
            )
            .map((id) => ({
                id,
                name: collectionNameByID?.get(id) ?? `Album ${id}`,
            }));

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
                let maxCount = 0;
                for (const comments of commentsMap.values()) {
                    const count = comments.filter((c) => !c.isDeleted).length;
                    if (count > maxCount) maxCount = count;
                }
                return maxCount;
            } else {
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
            const shouldAllowFileInfoArrowNavigation =
                openFileInfo &&
                !fileInfoNavigationLocked &&
                !event.shiftKey &&
                !event.metaKey &&
                !event.ctrlKey &&
                event.altKey &&
                (event.key == "ArrowLeft" || event.key == "ArrowRight");

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

    // Updating callbacks in place preserves the current zoom and pan state.
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

    useEffect(() => {
        if (!files.length) {
            handleClose();
        } else if (open && activeAnnotatedFile) {
            // PhotoSwipe has no valid current-slide state before annotation completes.
            psRef.current?.refreshSlideOnFilesUpdateIfNeeded();
        }
    }, [handleClose, files, open, activeAnnotatedFile]);

    useEffect(() => {
        if (open && files.length) {
            psRef.current?.refreshCurrentSlideFavoriteButtonIfNeeded();
        }
    }, [favoriteFileIDs, pendingFavoriteUpdates, files, open]);

    useEffect(() => {
        if (open && files.length) {
            psRef.current?.refreshCurrentSlideLikeButtonIfNeeded();
        }
    }, [allReactions, files, open]);

    const activeFileID = activeAnnotatedFile?.file.id;
    useEffect(() => {
        if (!open || !activeFileID) return;

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

    useEffect(() => {
        if (open && files.length) {
            psRef.current?.refreshCurrentSlideCommentCountIfNeeded();
        }
    }, [fileComments, files, open]);

    const SOCIAL_REFRESH_INTERVAL_MS = 5_000;

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
                const cached = collectionCacheRef.current.get(collectionId);
                if (!cached) continue;

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

    useInterval(
        refreshSocialData,
        openComments || openLikes ? SOCIAL_REFRESH_INTERVAL_MS : null,
    );

    useEffect(() => {
        if (open) {
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
                log.debug(() => "Closing file viewer");
                pswp.closeIfNeeded();
            };
        } else {
            return undefined;
        }
        // Recreating PhotoSwipe discards the open viewer's state.
        // Social visibility changes through delegate callbacks.
        // It must not enter this dependency list.
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
                  await onRemoteFilesPull();
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
                    sx={{ borderColor: "fixed.dark.divider", pb: "14px" }}
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

    padding-block: 12px;
    min-height: auto;

    gap: 1;
    justify-content: space-between;
    align-items: center;

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
    onConfirm: () => Promise<void>;
};

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
        if (reason == "backdropClick" && phase == "loading") return;
        resetPhaseAndClose();
    };

    return (
        <TitledMiniDialog
            open={open}
            onClose={handleClose}
            title={t("trash_file_title")}
            sx={(theme) => ({
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
    Pick<FileViewerProps, "disableDownload"> & { haveUser: boolean };

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
    if (file.metadata.fileType !== FileType.image) return false;

    const extension = lowercaseExtension(fileFileName(file));
    let isRenderable = true;
    if (extension && needsJPEGConversion(extension)) {
        if (!isDesktop) {
            isRenderable = isHEICExtension(extension);
        }
    }
    return isRenderable;
};

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
