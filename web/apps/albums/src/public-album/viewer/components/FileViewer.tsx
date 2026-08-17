import {
    addPublicReaction,
    createAnonIdentity,
    deletePublicReaction,
    getPublicAnonProfiles,
    getPublicParticipantsMaskedEmails,
    getPublicSocialDiff,
    getStoredAnonIdentity,
} from "@/public-album/social/api/public-reaction";
import ContentCopyIcon from "@mui/icons-material/ContentCopy";
import FullscreenExitOutlinedIcon from "@mui/icons-material/FullscreenExitOutlined";
import FullscreenOutlinedIcon from "@mui/icons-material/FullscreenOutlined";
import {
    Dialog,
    DialogContent,
    DialogTitle,
    Menu,
    MenuItem,
    styled,
    Typography,
} from "@mui/material";
import { SpacedRow } from "ente-base/components/containers";
import { DialogCloseIconButton } from "ente-base/components/mui/DialogCloseIconButton";
import { useInterval, useIsSmallWidth } from "ente-base/components/utils/hooks";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import type { PublicAlbumsCredentials } from "ente-base/http";
import { formattedListJoin, ut } from "ente-base/i18n";
import log from "ente-base/log";
import { FileType } from "ente-media/file-type";
import type { EnteFile } from "ente-media/file.js";
import { t } from "i18next";
import React, { useCallback, useEffect, useRef, useState } from "react";
import { fileInfoExifForFile, type ItemData } from "../lib/data-source";
import {
    FileViewerPhotoSwipe,
    moreButtonID,
    moreMenuID,
    resetMoreMenuButtonOnMenuClose,
    type FileViewerPhotoSwipeDelegate,
} from "../lib/photoswipe";
import type { Comment, UnifiedReaction } from "../lib/social-types";
import { AddNameModal } from "./AddNameModal";
import { CommentsSidebar } from "./CommentsSidebar";
import { FileInfo, type FileInfoExif } from "./FileInfo";
import { LikesSidebar } from "./LikesSidebar";
import { PublicLikeModal } from "./PublicLikeModal";

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
    showFavorite: boolean;
    showDownload: "bar" | undefined;
    showDelete: boolean;
    showArchive: boolean;
    showCopyImage: boolean;
}

export interface FileViewerAnnotatedFile {
    file: EnteFile;
    annotation: FileViewerFileAnnotation;
    itemData: ItemData;
}

export type FileViewerInitialSidebar = "likes" | "comments";

export type FileViewerProps = ModalVisibilityProps & {
    files: EnteFile[];
    initialIndex: number;
    initialSidebar?: FileViewerInitialSidebar;
    highlightCommentID?: string;
    initialAnonUserNames?: Map<string, string>;
    disableDownload?: boolean;
    showFullscreenButton?: boolean;
    onDownload?: (file: EnteFile) => void;
    activeCollectionID?: number;
    publicAlbumsCredentials?: PublicAlbumsCredentials;
    shouldCloseOnBrowserBack?: boolean;
    disableEscapeClose?: boolean;
    disableGestureClose?: boolean;
    collectionKey?: string;
    onJoinAlbum?: () => void;
    enableComment?: boolean;
    enableJoin?: boolean;
};

export const FileViewer: React.FC<FileViewerProps> = ({
    open,
    onClose,
    files,
    initialIndex,
    initialSidebar,
    highlightCommentID,
    initialAnonUserNames,
    disableDownload,
    showFullscreenButton,
    onDownload,
    activeCollectionID,
    publicAlbumsCredentials,
    shouldCloseOnBrowserBack: shouldCloseOnBrowserBackOverride,
    disableEscapeClose = false,
    disableGestureClose = false,
    collectionKey,
    onJoinAlbum,
    enableComment = true,
    enableJoin = true,
}) => {
    const { onGenericError } = useBaseContext();
    const shouldCloseOnBrowserBack = shouldCloseOnBrowserBackOverride ?? true;

    // PhotoSwipe keeps one delegate for its lifetime.
    // Update its callbacks instead of recreating the viewer when props change.
    const delegateRef = useRef<
        FileViewerPhotoSwipeDelegate<FileViewerAnnotatedFile> | undefined
    >(undefined);

    const psRef = useRef<
        FileViewerPhotoSwipe<FileViewerAnnotatedFile> | undefined
    >(undefined);
    const handleCloseRef = useRef<() => void>(() => undefined);
    const browserBackStateRef = useRef<string | undefined>(undefined);

    // This is the last action target, not necessarily the visible slide.
    const [activeAnnotatedFile, setActiveAnnotatedFile] = useState<
        FileViewerAnnotatedFile | undefined
    >(undefined);

    const [activeFileExif, setActiveFileExif] = useState<
        FileInfoExif | undefined
    >(undefined);

    const [openFileInfo, setOpenFileInfo] = useState(false);
    const [openComments, setOpenComments] = useState(false);
    const [openLikes, setOpenLikes] = useState(false);
    const [openPublicLikeModal, setOpenPublicLikeModal] = useState(false);
    const [openAddNameModal, setOpenAddNameModal] = useState(false);
    const [moreMenuAnchorEl, setMoreMenuAnchorEl] =
        useState<HTMLElement | null>(null);
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
        () =>
            initialAnonUserNames ? new Map(initialAnonUserNames) : new Map(),
    );
    const [publicSocialDataStatusByFileID, setPublicSocialDataStatusByFileID] =
        useState<Map<number, "loading" | "ready">>(new Map());
    const publicSocialDataErrorReportedRef = useRef(false);
    const anonProfilesErrorReportedRef = useRef(false);

    const reportPublicSocialDataError = useCallback(
        (e: unknown) => {
            if (publicSocialDataErrorReportedRef.current) return;
            publicSocialDataErrorReportedRef.current = true;
            onGenericError(e);
        },
        [onGenericError],
    );

    const reportAnonProfilesError = useCallback(
        (e: unknown) => {
            if (anonProfilesErrorReportedRef.current) return;
            anonProfilesErrorReportedRef.current = true;
            onGenericError(e);
        },
        [onGenericError],
    );

    useEffect(() => {
        anonProfilesErrorReportedRef.current = false;
    }, [collectionKey]);

    useEffect(() => {
        if (!initialAnonUserNames?.size) return;

        setAnonUserNames((prev) => {
            let didChange = false;
            const next = new Map(prev);

            for (const [anonUserID, userName] of initialAnonUserNames) {
                if (next.get(anonUserID) === userName) continue;
                next.set(anonUserID, userName);
                didChange = true;
            }

            return didChange ? next : prev;
        });
    }, [initialAnonUserNames]);

    const allReactionsRef = useRef(allReactions);
    useEffect(() => {
        allReactionsRef.current = allReactions;
    }, [allReactions]);

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

    const handleClose = useCallback(() => {
        if (document.fullscreenElement) void document.exitFullscreen();
        setOpenFileInfo(false);
        setOpenComments(false);
        setOpenLikes(false);
        setOpenPublicLikeModal(false);
        setMoreMenuAnchorEl(null);
        setOpenShortcuts(false);
        setIsFullscreen(false);
        onClose();
    }, [onClose]);

    handleCloseRef.current = handleClose;

    const handleViewInfo = useCallback(
        (annotatedFile: FileViewerAnnotatedFile) => {
            setActiveFileExif(
                fileInfoExifForFile(annotatedFile.file, (exif) =>
                    setActiveFileExif(exif),
                ),
            );
            setOpenFileInfo(true);
        },
        [],
    );

    const handleFileInfoClose = useCallback(() => setOpenFileInfo(false), []);

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

    const haveUser = false;

    const requestGuestLikeIdentity = useCallback(() => {
        if (enableJoin) {
            setOpenPublicLikeModal(true);
        } else {
            setOpenAddNameModal(true);
        }
    }, [enableJoin]);

    const handleLikeClick = useCallback(() => {
        const file = activeAnnotatedFileRef.current?.file;
        if (!file || !publicAlbumsCredentials) {
            requestGuestLikeIdentity();
            return;
        }

        const fileId = file.id;
        const collectionId = file.collectionID;
        const storedAnonIdentity = getStoredAnonIdentity(collectionId);

        const fileReactionsMap = allReactionsRef.current.get(fileId);
        const collectionReactions = fileReactionsMap?.get(collectionId) ?? [];
        const existingReaction = collectionReactions.find(
            (r) =>
                r.reactionType === "green_heart" &&
                !r.commentID &&
                storedAnonIdentity &&
                r.anonUserID === storedAnonIdentity.anonUserID,
        );

        if (existingReaction) {
            void (async () => {
                try {
                    await deletePublicReaction(
                        publicAlbumsCredentials,
                        collectionId,
                        existingReaction.id,
                    );

                    setAllReactions((prev) => {
                        const next = new Map(prev);
                        const fileReactionsMap = new Map<
                            number,
                            UnifiedReaction[]
                        >(prev.get(fileId) ?? new Map());
                        const updatedReactions = (
                            fileReactionsMap.get(collectionId) ?? []
                        ).filter((r) => r.id !== existingReaction.id);
                        fileReactionsMap.set(collectionId, updatedReactions);
                        next.set(fileId, fileReactionsMap);
                        return next;
                    });
                } catch (e) {
                    log.error("Failed to delete public reaction", e);
                }
            })();
        } else if (storedAnonIdentity) {
            void (async () => {
                try {
                    if (!collectionKey) {
                        log.error("Missing collection key for public reaction");
                        return;
                    }
                    const reactionId = await addPublicReaction(
                        publicAlbumsCredentials,
                        collectionId,
                        fileId,
                        "green_heart",
                        collectionKey,
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
                                userID: 0,
                                anonUserID: storedAnonIdentity.anonUserID,
                                isDeleted: false,
                                createdAt: Date.now() * 1000,
                                updatedAt: Date.now() * 1000,
                            },
                        ]);
                        next.set(fileId, fileReactionsMap);
                        return next;
                    });
                } catch (e) {
                    log.error("Failed to add public reaction", e);
                }
            })();
        } else {
            requestGuestLikeIdentity();
        }
    }, [publicAlbumsCredentials, collectionKey, requestGuestLikeIdentity]);

    const handlePublicLikeModalClose = useCallback(
        () => setOpenPublicLikeModal(false),
        [],
    );

    const handleLikeAnonymously = useCallback(() => {
        setOpenPublicLikeModal(false);
        setOpenAddNameModal(true);
    }, []);

    const handleJoinAlbumToLike = useCallback(() => {
        setOpenPublicLikeModal(false);
        onJoinAlbum?.();
    }, [onJoinAlbum]);

    const handleAddNameModalClose = useCallback(
        () => setOpenAddNameModal(false),
        [],
    );

    const handleAddNameSubmit = useCallback(
        (name: string) => {
            const file = activeAnnotatedFileRef.current?.file;
            if (!file || !publicAlbumsCredentials || !collectionKey) {
                log.error(
                    "Missing file, credentials, or collection key for public reaction",
                );
                setOpenAddNameModal(false);
                return;
            }

            const fileId = file.id;
            // Public album gallery mode uses collection ID 0 as a sentinel.
            const collectionId =
                activeCollectionID && activeCollectionID > 0
                    ? activeCollectionID
                    : file.collectionID;

            void (async () => {
                try {
                    let identity = getStoredAnonIdentity(collectionId);
                    if (!identity) {
                        identity = await createAnonIdentity(
                            publicAlbumsCredentials,
                            collectionId,
                            name,
                            collectionKey,
                        );
                    }

                    const reactionId = await addPublicReaction(
                        publicAlbumsCredentials,
                        collectionId,
                        fileId,
                        "green_heart",
                        collectionKey,
                        identity,
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
                                // Anonymous users use userID 0.
                                userID: 0,
                                anonUserID: identity.anonUserID,
                                isDeleted: false,
                                createdAt: Date.now() * 1000,
                                updatedAt: Date.now() * 1000,
                            },
                        ]);
                        next.set(fileId, fileReactionsMap);
                        return next;
                    });

                    setAnonUserNames((prev) => {
                        const next = new Map(prev);
                        next.set(identity.anonUserID, name);
                        return next;
                    });

                    setOpenAddNameModal(false);
                    setOpenLikes(true);
                } catch (e) {
                    log.error("Failed to add public reaction", e);
                    onGenericError(e);
                    setOpenAddNameModal(false);
                }
            })();
        },
        [
            activeCollectionID,
            publicAlbumsCredentials,
            collectionKey,
            onGenericError,
        ],
    );

    const handleDownloadBarAction = useCallback(
        (annotatedFile: FileViewerAnnotatedFile) => {
            onDownload!(annotatedFile.file);
        },
        [onDownload],
    );

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

    const handleCopyImage = useCallback(() => {
        handleMoreMenuCloseIfNeeded();
        if (!activeAnnotatedFile) return;
        const { imageURL } = activeAnnotatedFile.itemData;
        if (!imageURL) return;
        // Safari requires clipboard.write during the click event.
        // It accepts a promise for the blob.
        void window.navigator.clipboard
            .write([
                new ClipboardItem({
                    "image/png": createImagePNGBlob(imageURL),
                }),
            ])
            .catch(onGenericError);
    }, [onGenericError, handleMoreMenuCloseIfNeeded, activeAnnotatedFile]);

    const handleAnnotate = useCallback(
        (file: EnteFile, itemData: ItemData): FileViewerAnnotatedFile => {
            const fileID = file.id;
            const showDownload =
                disableDownload || !onDownload ? undefined : "bar";

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
                showFavorite: false,
                showDownload,
                showDelete: false,
                showArchive: false,
                showCopyImage,
            };

            const annotatedFile = { file, annotation, itemData };
            setActiveAnnotatedFile(annotatedFile);
            return annotatedFile;
        },
        [disableDownload, onDownload],
    );
    const showSocialButtons = true;

    const shouldShowSocialButtons_ = useCallback((): boolean => false, []);

    const getFiles = useCallback(() => files, [files]);

    const isFavorite = useCallback(() => undefined, []);

    const isFavoritePending = useCallback(() => false, []);

    const toggleFavorite = useCallback(() => Promise.resolve(undefined), []);

    const isLiked = useCallback(
        ({ file }: FileViewerAnnotatedFile) => {
            const fileReactionsMap = allReactions.get(file.id);
            if (!fileReactionsMap) return false;

            for (const [collectionId, reactions] of fileReactionsMap) {
                const storedAnonIdentity = getStoredAnonIdentity(collectionId);

                const hasUserLike = reactions.some((r) => {
                    if (r.commentID || r.reactionType !== "green_heart")
                        return false;
                    if (
                        storedAnonIdentity &&
                        r.anonUserID === storedAnonIdentity.anonUserID
                    )
                        return true;
                    return false;
                });
                if (hasUserLike) return true;
            }
            return false;
        },
        [allReactions],
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

    const shouldIgnoreKeyboardEvent = useCallback(() => {
        if (
            openFileInfo ||
            openComments ||
            openLikes ||
            openPublicLikeModal ||
            !!moreMenuAnchorEl ||
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
    }, [
        openFileInfo,
        openComments,
        openLikes,
        openPublicLikeModal,
        moreMenuAnchorEl,
        openShortcuts,
    ]);

    const canCopyImage = useCallback(
        () =>
            activeAnnotatedFile?.annotation.showCopyImage &&
            !!activeAnnotatedFile.itemData.imageURL,
        [activeAnnotatedFile],
    );

    const performKeyAction = useCallback<
        FileViewerPhotoSwipeDelegate<FileViewerAnnotatedFile>["performKeyAction"]
    >(
        (action) => {
            switch (action) {
                case "delete":
                    break;
                case "toggle-archive":
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
            handleCopyImage,
            handleToggleFullscreen,
            handleShortcuts,
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
            // Refreshing while the viewer closes can race navigation.
            psRef.current?.refreshSlideOnFilesUpdateIfNeeded();
        }
    }, [handleClose, files, open, activeAnnotatedFile]);

    useEffect(() => {
        if (open && files.length) {
            psRef.current?.refreshCurrentSlideLikeButtonIfNeeded();
        }
    }, [allReactions, files, open]);

    const activeFileID = activeAnnotatedFile?.file.id;
    const shouldFetchPublicSocialData =
        open &&
        enableComment &&
        !!activeFileID &&
        !!publicAlbumsCredentials &&
        !!collectionKey;
    const isInitialPublicSocialDataLoading =
        !!activeFileID &&
        shouldFetchPublicSocialData &&
        publicSocialDataStatusByFileID.get(activeFileID) !== "ready";

    useEffect(() => {
        if (
            !open ||
            !enableComment ||
            !activeFileID ||
            !publicAlbumsCredentials ||
            !collectionKey
        )
            return;

        const file = files.find((f) => f.id === activeFileID);
        if (!file) return;

        publicSocialDataErrorReportedRef.current = false;

        setPublicSocialDataStatusByFileID((prev) => {
            if (prev.get(activeFileID) === "ready") return prev;

            const next = new Map(prev);
            next.set(activeFileID, "loading");
            return next;
        });

        void (async () => {
            try {
                const { comments, reactions, decryptionError } =
                    await getPublicSocialDiff(
                        publicAlbumsCredentials,
                        activeFileID,
                        collectionKey,
                    );
                if (decryptionError) {
                    reportPublicSocialDataError(decryptionError);
                } else {
                    publicSocialDataErrorReportedRef.current = false;
                }

                const commentsForFile: Comment[] = comments.map((c) => ({
                    id: c.id,
                    collectionID: c.collectionID,
                    fileID: c.fileID,
                    parentCommentID: c.parentCommentID,
                    userID: c.userID,
                    anonUserID: c.anonUserID,
                    text: c.text,
                    isDeleted: c.isDeleted,
                    createdAt: c.createdAt,
                    updatedAt: c.updatedAt,
                }));

                const commentsMap = new Map<number, Comment[]>();
                commentsMap.set(file.collectionID, commentsForFile);

                setFileComments((prev) => {
                    const next = new Map(prev);
                    next.set(activeFileID, commentsMap);
                    return next;
                });

                const unifiedReactions: UnifiedReaction[] = reactions.map(
                    (r) => ({
                        id: r.id,
                        collectionID: file.collectionID,
                        fileID: r.fileID,
                        commentID: r.commentID,
                        reactionType: r.reactionType,
                        userID: r.userID,
                        anonUserID: r.anonUserID,
                        isDeleted: r.isDeleted,
                        createdAt: r.createdAt,
                        updatedAt: r.updatedAt,
                    }),
                );

                const reactionsMap = new Map<number, UnifiedReaction[]>();
                reactionsMap.set(file.collectionID, unifiedReactions);

                setAllReactions((prev) => {
                    const next = new Map(prev);
                    next.set(activeFileID, reactionsMap);
                    return next;
                });

                try {
                    const { anonUserNames: anonProfiles, decryptionError } =
                        await getPublicAnonProfiles(
                            publicAlbumsCredentials,
                            collectionKey,
                        );
                    if (decryptionError) {
                        reportAnonProfilesError(decryptionError);
                    } else {
                        anonProfilesErrorReportedRef.current = false;
                    }
                    setAnonUserNames((prev) => {
                        const next = new Map(prev);
                        for (const [id, name] of anonProfiles) {
                            next.set(id, name);
                        }
                        return next;
                    });
                } catch (e) {
                    reportAnonProfilesError(e);
                }

                try {
                    const participantEmails =
                        await getPublicParticipantsMaskedEmails(
                            publicAlbumsCredentials,
                        );
                    setUserIDToEmail((prev) => {
                        const next = new Map(prev);
                        for (const [id, email] of participantEmails) {
                            next.set(id, email);
                        }
                        return next;
                    });
                } catch {
                    // Names are optional enrichment.
                }
            } catch (e) {
                reportPublicSocialDataError(e);
            } finally {
                setPublicSocialDataStatusByFileID((prev) => {
                    if (prev.get(activeFileID) === "ready") return prev;

                    const next = new Map(prev);
                    next.set(activeFileID, "ready");
                    return next;
                });
            }
        })();
    }, [
        open,
        enableComment,
        activeFileID,
        publicAlbumsCredentials,
        collectionKey,
        files,
        reportAnonProfilesError,
        reportPublicSocialDataError,
    ]);

    useEffect(() => {
        if (open && files.length) {
            psRef.current?.refreshCurrentSlideCommentCountIfNeeded();
        }
    }, [fileComments, files, open]);

    const SOCIAL_REFRESH_INTERVAL_MS = 5_000;

    const refreshPublicSocialData = useCallback(async () => {
        if (
            !activeFileID ||
            !publicAlbumsCredentials ||
            !collectionKey ||
            !enableComment
        )
            return;

        const file = files.find((f) => f.id === activeFileID);
        if (!file) return;

        try {
            const { comments, reactions, decryptionError } =
                await getPublicSocialDiff(
                    publicAlbumsCredentials,
                    activeFileID,
                    collectionKey,
                );
            if (decryptionError) {
                reportPublicSocialDataError(decryptionError);
            } else {
                publicSocialDataErrorReportedRef.current = false;
            }

            const commentsForFile: Comment[] = comments.map((c) => ({
                id: c.id,
                collectionID: c.collectionID,
                fileID: c.fileID,
                parentCommentID: c.parentCommentID,
                userID: c.userID,
                anonUserID: c.anonUserID,
                text: c.text,
                isDeleted: c.isDeleted,
                createdAt: c.createdAt,
                updatedAt: c.updatedAt,
            }));

            const commentsMap = new Map<number, Comment[]>();
            commentsMap.set(file.collectionID, commentsForFile);

            setFileComments((prev) => {
                const next = new Map(prev);
                next.set(activeFileID, commentsMap);
                return next;
            });

            const unifiedReactions: UnifiedReaction[] = reactions.map((r) => ({
                id: r.id,
                collectionID: file.collectionID,
                fileID: r.fileID,
                commentID: r.commentID,
                reactionType: r.reactionType,
                userID: r.userID,
                anonUserID: r.anonUserID,
                isDeleted: r.isDeleted,
                createdAt: r.createdAt,
                updatedAt: r.updatedAt,
            }));

            const reactionsMap = new Map<number, UnifiedReaction[]>();
            reactionsMap.set(file.collectionID, unifiedReactions);

            setAllReactions((prev) => {
                const next = new Map(prev);
                next.set(activeFileID, reactionsMap);
                return next;
            });

            try {
                const { anonUserNames: anonProfiles, decryptionError } =
                    await getPublicAnonProfiles(
                        publicAlbumsCredentials,
                        collectionKey,
                    );
                if (decryptionError) {
                    reportAnonProfilesError(decryptionError);
                } else {
                    anonProfilesErrorReportedRef.current = false;
                }
                setAnonUserNames((prev) => {
                    const next = new Map(prev);
                    for (const [id, name] of anonProfiles) {
                        next.set(id, name);
                    }
                    return next;
                });
            } catch (e) {
                reportAnonProfilesError(e);
            }
            // Masked participant emails are stable enough to fetch only on open.
        } catch (e) {
            reportPublicSocialDataError(e);
        }
    }, [
        activeFileID,
        publicAlbumsCredentials,
        collectionKey,
        enableComment,
        files,
        reportAnonProfilesError,
        reportPublicSocialDataError,
    ]);

    useInterval(
        refreshPublicSocialData,
        (openComments || openLikes) && publicAlbumsCredentials
            ? SOCIAL_REFRESH_INTERVAL_MS
            : null,
    );

    useEffect(() => {
        if (open) {
            log.debug(() => "Opening file viewer");

            const pswp = new FileViewerPhotoSwipe({
                initialIndex,
                showSocialButtons,
                enableComment,
                showFullscreenButton,
                disableEscapeClose,
                disableGestureClose,
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
        // Changing these dependencies recreates PhotoSwipe.
        // showSocialButtons and enableComment deliberately stay out.
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [
        open,
        onClose,
        initialIndex,
        disableDownload,
        showFullscreenButton,
        disableEscapeClose,
        disableGestureClose,
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

        // Back closes the overlay without leaving the shared link.
        const stateMarker = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
        browserBackStateRef.current = stateMarker;

        const currentState: unknown = window.history.state;
        const viewerState = addFileViewerBackStateMarker(
            currentState,
            stateMarker,
        );
        window.history.pushState(viewerState, "", window.location.href);

        const handlePopState = (event: PopStateEvent) => {
            if (browserBackStateRef.current != stateMarker) return;
            if (hasFileViewerBackStateMarker(event.state, stateMarker)) return;
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
            />
            <CommentsSidebar
                open={openComments}
                onClose={handleCommentsClose}
                file={activeAnnotatedFile.file}
                activeCollectionID={activeCollectionID}
                isSocialDataLoading={isInitialPublicSocialDataLoading}
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
                publicAlbumsCredentials={publicAlbumsCredentials}
                collectionKey={collectionKey}
                anonUserNames={anonUserNames}
                onJoinAlbum={onJoinAlbum}
                enableJoin={enableJoin}
            />
            <LikesSidebar
                open={openLikes}
                onClose={handleLikesClose}
                file={activeAnnotatedFile.file}
                activeCollectionID={activeCollectionID}
                isSocialDataLoading={isInitialPublicSocialDataLoading}
                prefetchedReactions={allReactions.get(
                    activeAnnotatedFile.file.id,
                )}
                prefetchedUserIDToEmail={userIDToEmail}
                anonUserNames={anonUserNames}
            />
            <PublicLikeModal
                open={openPublicLikeModal}
                onClose={handlePublicLikeModalClose}
                onLikeAnonymously={handleLikeAnonymously}
                onJoinAlbumToLike={handleJoinAlbumToLike}
                enableJoin={enableJoin}
            />
            <AddNameModal
                open={openAddNameModal}
                onClose={handleAddNameModalClose}
                onSubmit={handleAddNameSubmit}
            />
            <MoreMenu
                open={!!moreMenuAnchorEl}
                onClose={handleMoreMenuCloseIfNeeded}
                anchorEl={moreMenuAnchorEl}
                id={moreMenuID}
                disableAutoFocusItem
                slotProps={{ list: { "aria-labelledby": moreButtonID } }}
            >
                {canCopyImage() && (
                    <MoreMenuItem onClick={handleCopyImage}>
                        <MoreMenuItemTitle>
                            {t("copy_as_png")}
                        </MoreMenuItemTitle>
                        <ContentCopyIcon sx={{ "&&": { fontSize: "18px" } }} />
                    </MoreMenuItem>
                )}

                <MoreMenuItem
                    onClick={handleToggleFullscreen}
                    sx={{
                        ...(canCopyImage()
                            ? {
                                  borderTop: 1,
                                  borderColor: "fixed.dark.divider",
                                  mt: "2px",
                                  pt: "14px",
                              }
                            : undefined),
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

// Override MUI's responsive min-height so menu rows remain 44px.
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
