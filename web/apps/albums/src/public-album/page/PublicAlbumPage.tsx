// TODO: Audit this file (too many null assertions + other issues)
/* eslint-disable @typescript-eslint/no-floating-promises */
import { useAlbumsAppContext } from "@/app/context/albums-app-context";
import { LazyNotification } from "@/app/lazy/global-ui";
import {
    PasswordUnlockScreen,
    type PasswordUnlockScreenProps,
} from "@/public-album/access/components/PasswordUnlockScreen";
import { getEnteURL } from "@/public-album/access/utils/external-links";
import {
    AddPhotosIcon,
    DownloadIcon,
    FeedIcon,
    ShareIcon,
} from "@/public-album/components/ActionIcons";
import type { FileListHeaderOrFooter } from "@/public-album/components/FileList";
import { FileListWithViewer } from "@/public-album/components/FileListWithViewer";
import type { TripLayoutProps } from "@/public-album/components/TripLayout";
import { setPublicAlbumsCredentials } from "@/public-album/data/auth/public-link-credentials";
import { ActiveDownloadStatusNotifications } from "@/public-album/download/components/ActiveDownloadStatusNotifications";
import { downloadManager } from "@/public-album/download/services/download-manager";
import { thumbnailManager } from "@/public-album/media/thumbnails/thumbnail-manager";
import { sortFiles } from "@/public-album/media/utils/sort-files";
import type { UploadProps } from "@/public-album/upload/components/Upload";
import {
    getSelectedFiles,
    type SelectedState,
} from "@/public-album/utils/file";
import type { FileViewerInitialSidebar } from "@/public-album/viewer/components/FileViewer";
import type { PublicAlbumSingleFileViewerProps } from "@/public-album/viewer/components/PublicAlbumSingleFileViewer";
import type { PublicFeedItemClickInfo } from "@/public-album/viewer/components/PublicFeedSidebar";
import { LazyPublicFeedSidebar } from "@/public-album/viewer/lib/lazy";
import CheckIcon from "@mui/icons-material/Check";
import CloseIcon from "@mui/icons-material/Close";
import {
    Box,
    Button,
    IconButton,
    Stack,
    styled,
    Tooltip,
    useMediaQuery,
} from "@mui/material";
import Typography from "@mui/material/Typography";
import { SpacedRow, Stack100vhCenter } from "ente-base/components/containers";
import { EnteLogo } from "ente-base/components/EnteLogo";
import {
    LoadingIndicator,
    TranslucentLoadingOverlay,
} from "ente-base/components/loaders";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { NavbarBase } from "ente-base/components/Navbar";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import { isDevBuild } from "ente-base/env";
import {
    isHTTP401Error,
    isHTTPErrorWithStatus,
    isMuseumHTTPError,
    type PublicAlbumsCredentials,
} from "ente-base/http";
import log from "ente-base/log";
import { apiOrigin, isCustomAPIOrigin } from "ente-base/origins";
import type { FullScreenDropZoneProps } from "ente-gallery/components/FullScreenDropZone";
import {
    useSaveGroupsActions,
    type AddSaveGroup,
} from "ente-gallery/components/utils/save-groups";
import { quickLinkDateRangeForFiles } from "ente-gallery/utils/quick-link";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { fileFileName } from "ente-media/file-metadata";
import { FileType } from "ente-media/file-type";
import {
    GalleryItemsHeaderAdapter,
    GalleryItemsSummary,
} from "ente-new/photos/components/gallery/ListHeader";
import {
    LoadingThumbnail,
    StaticThumbnail,
} from "ente-new/photos/components/PlaceholderThumbnails";
import { thumbnailGap } from "ente-new/photos/components/utils/thumbnail-grid-layout";
import { t } from "i18next";
import dynamic from "next/dynamic";
import { useRouter } from "next/router";
import {
    useCallback,
    useEffect,
    useMemo,
    useRef,
    useState,
    type ComponentType,
    type PropsWithChildren,
} from "react";
import type { FileWithPath } from "react-dropzone";

const LazyPublicAlbumSingleFileViewer =
    dynamic<PublicAlbumSingleFileViewerProps>(
        () =>
            import("@/public-album/viewer/components/PublicAlbumSingleFileViewer").then(
                ({ PublicAlbumSingleFileViewer }) =>
                    PublicAlbumSingleFileViewer,
            ),
        { ssr: false, loading: () => <LoadingIndicator /> },
    );

const LazyTripLayout = dynamic<TripLayoutProps>(
    () =>
        import("@/public-album/components/TripLayout").then(
            ({ TripLayout }) => TripLayout,
        ),
    { ssr: false, loading: () => <LoadingIndicator /> },
);

const LazyUpload = dynamic<UploadProps>(
    () =>
        import("@/public-album/upload/components/Upload").then(
            ({ Upload }) => Upload,
        ),
    { ssr: false },
);

const loadPublicAlbumsFDB = () =>
    import("@/public-album/data/storage/public-albums-fdb");

const loadPublicCollectionService = () =>
    import("@/public-album/data/api/public-collection");

const loadShareService = () =>
    import("@/public-album/access/services/extract-collection-key");

const loadJoinPublicAlbumRedirect = () =>
    import("@/public-album/access/services/join-public-album-redirect");

const publicAlbumAllFilesCollectionID = 0;

const isDeviceLimitExceededError = async (e: unknown) =>
    isHTTPErrorWithStatus(e, 429) ||
    (await isMuseumHTTPError(e, 403, "LINK_DEVICE_LIMIT_EXCEEDED"));

const accessTokenFromURL = (url: URL) =>
    url.searchParams.get("t") || url.pathname.split("/").find(Boolean);

export default function PublicAlbumPage() {
    const { showMiniDialog, onGenericError } = useBaseContext();
    const { showLoadingBar, hideLoadingBar } = useAlbumsAppContext();

    const [publicCollection, setPublicCollection] = useState<
        Collection | undefined
    >(undefined);
    const [publicFiles, setPublicFiles] = useState<EnteFile[] | undefined>(
        undefined,
    );
    const [errorMessage, setErrorMessage] = useState<string>("");
    const [loading, setLoading] = useState(true);
    const [isPasswordProtected, setIsPasswordProtected] = useState(false);
    const [uploadTypeSelectorView, setUploadTypeSelectorView] = useState(false);
    const [blockingLoad, setBlockingLoad] = useState(false);
    const [shouldDisableDropzone, setShouldDisableDropzone] = useState(false);
    const [isUploadInProgress, setIsUploadInProgress] = useState(false);
    const [shouldRenderUpload, setShouldRenderUpload] = useState(false);
    const [dragAndDropFiles, setDragAndDropFiles] = useState<FileWithPath[]>(
        [],
    );
    const [selected, setSelected] = useState<SelectedState>({ count: 0 });

    // TODO: Can we convert these to state
    const credentials = useRef<PublicAlbumsCredentials | undefined>(undefined);
    const collectionKey = useRef<string | undefined>(undefined);

    const isRedirectingToAlbumsAppRef = useRef<boolean>(false);

    const { onAddSaveGroup } = useSaveGroupsActions();
    const { show: showPublicFeed, props: publicFeedVisibilityProps } =
        useModalVisibility();
    const [keepPublicFeedSidebarMounted, setKeepPublicFeedSidebarMounted] =
        useState(false);
    const publicFeedSidebarOpenRef = useRef(publicFeedVisibilityProps.open);

    // Pending navigation from feed item click
    const [pendingFileNavigation, setPendingFileNavigation] = useState<{
        fileIndex: number;
        sidebar?: FileViewerInitialSidebar;
        commentID?: string;
        anonUserNames?: Map<string, string>;
    }>();

    useEffect(() => {
        publicFeedSidebarOpenRef.current = publicFeedVisibilityProps.open;
        if (publicFeedVisibilityProps.open) {
            setKeepPublicFeedSidebarMounted(true);
        }
    }, [publicFeedVisibilityProps.open]);

    const handlePublicFeedSidebarExited = useCallback(() => {
        if (!publicFeedSidebarOpenRef.current) {
            setKeepPublicFeedSidebarMounted(false);
        }
    }, []);

    /**
     * Handle clicks on feed items to navigate to the file and open sidebar.
     */
    const handleFeedItemClick = (info: PublicFeedItemClickInfo) => {
        if (!publicFiles) return;

        // Find the file index in publicFiles
        const fileIndex = publicFiles.findIndex((f) => f.id === info.fileID);
        if (fileIndex === -1) return;

        // Close the feed sidebar
        publicFeedVisibilityProps.onClose();

        // Determine which sidebar to open
        const sidebar: FileViewerInitialSidebar =
            info.type === "liked_photo" || info.type === "liked_video"
                ? "likes"
                : "comments";

        // Set navigation state
        setPendingFileNavigation({
            fileIndex,
            sidebar,
            commentID: info.commentID,
            anonUserNames: info.anonUserNames
                ? new Map(info.anonUserNames)
                : undefined,
        });
    };

    const router = useRouter();

    const showPublicLinkExpiredMessage = () =>
        showMiniDialog({
            title: t("link_expired"),
            message: t("link_expired_message"),
            nonClosable: true,
            continue: {
                text: t("login"),
                action: async () => {
                    if (isCustomAPIOrigin) {
                        await router.push("/");
                    } else {
                        window.location.href = "https://photos.ente.com";
                    }
                },
            },
            cancel: false,
        });

    /**
     * Check if we need to redirect Trip albums from custom domains to albums.ente.com
     * Returns true if a redirect was initiated, false otherwise.
     * Reason: custom domains do not support the Trip layout fully
     */
    const checkAndRedirectForTripAlbum = (collection: Collection): boolean => {
        if (
            isCustomAPIOrigin ||
            collection.pubMagicMetadata?.data.layout !== "trip"
        ) {
            return false;
        }

        const currentURL = new URL(window.location.href);
        const albumsURL = new URL("https://albums.ente.com");

        if (currentURL.host === albumsURL.host) {
            return false;
        }

        isRedirectingToAlbumsAppRef.current = true;

        albumsURL.pathname = currentURL.pathname;
        albumsURL.search = currentURL.search;
        albumsURL.hash = currentURL.hash;

        window.location.href = albumsURL.href;
        return true;
    };

    useEffect(() => {
        /**
         * Determine credentials, read the locally cached state, then start
         * pulling the latest from remote.
         */
        const main = async () => {
            let redirectingToWebsite = false;
            try {
                const currentURL = new URL(window.location.href);
                const accessToken = accessTokenFromURL(currentURL);
                const [
                    { extractCollectionKeyFromShareURL },
                    {
                        savedPublicCollectionLinkDeviceToken,
                        savedPublicCollectionAccessTokenJWT,
                        savedPublicCollectionByKey,
                        savedPublicCollectionFiles,
                    },
                ] = await Promise.all([
                    loadShareService(),
                    loadPublicAlbumsFDB(),
                ]);
                const ck = await extractCollectionKeyFromShareURL(currentURL);
                if (!accessToken && !ck) {
                    // Only redirect to ente.com if this is not a self-hosted instance.
                    if (!isCustomAPIOrigin) {
                        window.location.href = "https://ente.com";
                        redirectingToWebsite = true;
                    }
                }
                if (!accessToken || !ck) {
                    return;
                }
                collectionKey.current = ck;
                const collection = await savedPublicCollectionByKey(ck);
                const currentAPIOrigin = await apiOrigin();
                let accessTokenJWT: string | undefined;
                const linkDeviceToken =
                    await savedPublicCollectionLinkDeviceToken(
                        currentAPIOrigin,
                        accessToken,
                    );
                if (collection) {
                    setPublicCollection(collection);
                    setIsPasswordProtected(
                        !!collection.publicURLs[0]?.passwordEnabled,
                    );
                    setPublicFiles(
                        sortFilesForCollection(
                            await savedPublicCollectionFiles(accessToken),
                            collection,
                        ),
                    );
                    accessTokenJWT =
                        await savedPublicCollectionAccessTokenJWT(accessToken);
                }
                credentials.current = {
                    accessToken,
                    accessTokenJWT,
                    linkDeviceToken,
                };
                setPublicAlbumsCredentials(credentials.current);
                await publicAlbumsRemotePull();
            } finally {
                if (
                    !redirectingToWebsite &&
                    !isRedirectingToAlbumsAppRef.current
                ) {
                    setLoading(false);
                }
            }
        };
        main();
        // TODO:
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    const downloadEnabled =
        publicCollection?.publicURLs[0]?.enableDownload ?? true;
    const collectEnabled =
        publicCollection?.publicURLs[0]?.enableCollect ?? false;

    useEffect(() => {
        if (!collectEnabled) return;
        void import("@/public-album/upload/pipeline").then(
            ({ updateShouldDisableCFUploadProxy }) =>
                updateShouldDisableCFUploadProxy(),
        );
    }, [collectEnabled]);

    useEffect(() => {
        if (
            uploadTypeSelectorView ||
            dragAndDropFiles.length > 0 ||
            isUploadInProgress
        ) {
            setShouldRenderUpload(true);
        }
    }, [dragAndDropFiles.length, isUploadInProgress, uploadTypeSelectorView]);

    /**
     * Pull the latest data related to the public album from remote, updating
     * both our local database and component state.
     */
    const publicAlbumsRemotePull = useCallback(async () => {
        const accessToken = credentials.current!.accessToken;
        showLoadingBar();
        setLoading(true);
        try {
            const [
                {
                    pullCollection,
                    pullPublicCollectionFiles,
                    removePublicCollectionFileData,
                },
                {
                    removePublicCollectionAccessTokenJWT,
                    savePublicCollectionLinkDeviceToken,
                },
            ] = await Promise.all([
                loadPublicCollectionService(),
                loadPublicAlbumsFDB(),
            ]);
            const { collection, linkDeviceToken } = await pullCollection(
                credentials.current!,
                collectionKey.current!,
            );
            if (linkDeviceToken) {
                credentials.current!.linkDeviceToken = linkDeviceToken;
                setPublicAlbumsCredentials(credentials.current);
                await savePublicCollectionLinkDeviceToken(
                    await apiOrigin(),
                    accessToken,
                    linkDeviceToken,
                );
            }

            if (checkAndRedirectForTripAlbum(collection)) {
                return;
            }

            setPublicCollection(collection);
            const isPasswordProtected =
                !!collection.publicURLs[0]?.passwordEnabled;
            setIsPasswordProtected(isPasswordProtected);
            setErrorMessage("");

            // Remove the locally cached accessTokenJWT if the sharer has
            // disabled password protection on the link.
            if (!isPasswordProtected && credentials.current?.accessTokenJWT) {
                credentials.current.accessTokenJWT = undefined;
                setPublicAlbumsCredentials(credentials.current);
                removePublicCollectionAccessTokenJWT(accessToken);
            }

            if (isPasswordProtected && !credentials.current?.accessTokenJWT) {
                await removePublicCollectionFileData(accessToken);
            } else {
                try {
                    await pullPublicCollectionFiles(
                        credentials.current!,
                        collection,
                        (files) =>
                            setPublicFiles(
                                sortFilesForCollection(files, collection),
                            ),
                    );
                } catch (e) {
                    // If we reached the try block and attempted to pull files,
                    // it means the accessToken itself is very likely valid
                    // (since the `pullCollection` succeeded just a moment ago).
                    //
                    // So a 401 Unauthorized now indicates that the
                    // accessTokenJWT is no longer valid since the sharer has
                    // changed the password.
                    //
                    // Clear the locally cached accessTokenJWT and ask the user
                    // to reenter the password.
                    if (isHTTP401Error(e)) {
                        credentials.current!.accessTokenJWT = undefined;
                        setPublicAlbumsCredentials(credentials.current);
                    } else {
                        throw e;
                    }
                }
            }
        } catch (e) {
            const isDeviceLimitExceeded = await isDeviceLimitExceededError(e);
            // The 410 Gone or device-limit failure can arise from either the
            // collection pull or the files pull since they're part of the
            // remote's access token check sequence.
            //
            // In practice, it almost always will be a consequence of the
            // collection pull since it happens first.
            //
            // The 401 Unauthorized can only arise from the collection pull
            // since we already handle that separately for the files pull.
            if (
                isHTTPErrorWithStatus(e, 401) ||
                isHTTPErrorWithStatus(e, 410) ||
                isDeviceLimitExceeded
            ) {
                const [
                    { removePublicCollectionFileData },
                    { removePublicCollectionByKey },
                ] = await Promise.all([
                    loadPublicCollectionService(),
                    loadPublicAlbumsFDB(),
                ]);
                setErrorMessage(
                    isDeviceLimitExceeded
                        ? t("link_request_limit_exceeded")
                        : t("link_expired_message"),
                );
                // Sharing has been disabled. Clear out local cache.
                await removePublicCollectionFileData(accessToken);
                await removePublicCollectionByKey(collectionKey.current!);
                setPublicCollection(undefined);
                setPublicFiles(undefined);
            } else {
                log.error("Public album remote pull failed", e);
                // Don't use the `setErrorMessage`, show a dialog instead,
                // because this might be a transient network error.
                onGenericError(e);
            }
        } finally {
            hideLoadingBar();
            if (!isRedirectingToAlbumsAppRef.current) {
                setLoading(false);
            }
        }
    }, [showLoadingBar, hideLoadingBar, onGenericError]);

    // See: [Note: Visual feedback to acknowledge user actions]
    const handleVisualFeedback = useCallback(() => {
        showLoadingBar();
        setTimeout(hideLoadingBar, 0);
    }, [showLoadingBar, hideLoadingBar]);

    const handleJoinAlbum = useCallback(() => {
        const accessToken = credentials.current?.accessToken;
        const currentCollectionKey = collectionKey.current;

        if (!publicCollection || !accessToken || !currentCollectionKey) {
            return;
        }

        void loadJoinPublicAlbumRedirect().then(
            ({ joinPublicAlbumViaRedirect }) =>
                joinPublicAlbumViaRedirect({
                    publicCollection,
                    accessToken,
                    collectionKey: currentCollectionKey,
                    credentials,
                }),
        );
    }, [publicCollection]);

    const handleSubmitPassword: PasswordUnlockScreenProps["onSubmit"] = async (
        password,
        setFieldError,
    ) => {
        try {
            const accessToken = credentials.current!.accessToken;
            const [
                { verifyPublicAlbumPassword },
                { savePublicCollectionAccessTokenJWT },
            ] = await Promise.all([
                import("@/public-album/access/services/verify-public-album-password"),
                loadPublicAlbumsFDB(),
            ]);
            const accessTokenJWT = await verifyPublicAlbumPassword(
                publicCollection!.publicURLs[0]!,
                password,
                accessToken,
            );
            credentials.current!.accessTokenJWT = accessTokenJWT;
            setPublicAlbumsCredentials(credentials.current);
            await savePublicCollectionAccessTokenJWT(
                accessToken,
                accessTokenJWT,
            );
        } catch (e) {
            log.error("Failed to verifyLinkPassword", e);
            if (isHTTP401Error(e)) {
                setFieldError(t("incorrect_password"));
                return;
            }
            throw e;
        }

        await publicAlbumsRemotePull();
    };

    const clearSelection = () => {
        if (!selected.count) {
            return;
        }
        setSelected({ count: 0 });
    };

    const handleUploadFile = (file: EnteFile) =>
        setPublicFiles(
            sortFilesForCollection([...publicFiles!, file], publicCollection),
        );

    const downloadFilesHelper = async () => {
        try {
            const { downloadAndSaveFiles } =
                await import("@/public-album/download/services/save");
            const selectedFiles = getSelectedFiles(selected, publicFiles!);
            const singleFile =
                selectedFiles.length === 1 ? selectedFiles[0] : undefined;
            const title =
                singleFile?.metadata.fileType === FileType.livePhoto
                    ? fileFileName(singleFile)
                    : t("files_count", { count: selectedFiles.length });
            await downloadAndSaveFiles(selectedFiles, title, onAddSaveGroup);
            clearSelection();
        } catch (e) {
            log.error("failed to download selected files", e);
        }
    };

    const onAddPhotos = useMemo(() => {
        if (!collectEnabled) return undefined;
        return () => {
            setShouldRenderUpload(true);
            setUploadTypeSelectorView(true);
        };
    }, [collectEnabled]);
    const emptyStateAction = useMemo(
        () =>
            onAddPhotos && !isUploadInProgress
                ? { label: t("add_photos"), onClick: onAddPhotos }
                : undefined,
        [onAddPhotos, isUploadInProgress],
    );

    const closeUploadTypeSelectorView = () => {
        setUploadTypeSelectorView(false);
    };

    const commentsEnabled =
        publicCollection?.publicURLs[0]?.enableComment ?? false;
    const joinEnabled =
        (isDevBuild || !isCustomAPIOrigin) &&
        (publicCollection?.publicURLs[0]?.enableJoin ?? false);
    const handleDrop = useCallback((files: FileWithPath[]) => {
        setShouldRenderUpload(true);
        setDragAndDropFiles(files);
    }, []);

    const hasSelection = selected.count > 0;
    const viewportWidth = useViewportWidth();
    const publicAlbumLayout = normalizedPublicAlbumLayout(
        publicCollection?.pubMagicMetadata?.data.layout,
    );
    const isMobileHeaderLayout = useMediaQuery("(width < 720px)");
    const showMobileMasonryCover =
        isMobileHeaderLayout && publicAlbumLayout === "masonry";
    const fileListHeaderHeightForViewport = isMobileHeaderLayout
        ? showMobileMasonryCover
            ? mobileMasonryFileListHeaderHeight(viewportWidth)
            : fileListHeaderHeightMobile
        : fileListHeaderHeight;

    const fileListHeader = useMemo<FileListHeaderOrFooter | undefined>(
        () =>
            publicCollection && publicFiles
                ? {
                      component: (
                          <FileListHeader
                              {...{
                                  publicCollection,
                                  publicFiles,
                                  downloadEnabled,
                                  onAddSaveGroup,
                                  onAddPhotos,
                                  onShowFeed: commentsEnabled
                                      ? showPublicFeed
                                      : undefined,
                                  addPhotosDisabled: isUploadInProgress,
                                  hasSelection,
                                  showMobileMasonryCover,
                              }}
                          />
                      ),
                      height: fileListHeaderHeightForViewport,
                  }
                : undefined,
        [
            onAddSaveGroup,
            publicCollection,
            publicFiles,
            downloadEnabled,
            showPublicFeed,
            commentsEnabled,
            onAddPhotos,
            isUploadInProgress,
            hasSelection,
            showMobileMasonryCover,
            fileListHeaderHeightForViewport,
        ],
    );

    const fileListFooterHeightForViewport = showMobileMasonryCover
        ? mobileMasonryFileListFooterHeight
        : fileListFooterHeight;

    const fileListFooter = useMemo<FileListHeaderOrFooter>(
        () => ({
            component: (
                <FileListFooter height={fileListFooterHeightForViewport} />
            ),
            height: fileListFooterHeightForViewport,
            extendToInlineEdges: true,
        }),
        [fileListFooterHeightForViewport],
    );

    if (loading && (!publicFiles || !credentials.current)) {
        return <LoadingIndicator />;
    } else if (errorMessage) {
        return (
            <Stack100vhCenter>
                <Typography
                    sx={{
                        color: "critical.main",
                        px: { xs: 2, sm: 0 },
                        textAlign: { xs: "center", sm: "inherit" },
                    }}
                >
                    {errorMessage}
                </Typography>
            </Stack100vhCenter>
        );
    } else if (isPasswordProtected && !credentials.current?.accessTokenJWT) {
        return <PasswordUnlockScreen onSubmit={handleSubmitPassword} />;
    } else if (!publicFiles || !credentials.current) {
        return (
            <Stack100vhCenter>
                <Typography>{t("not_found")}</Typography>
            </Stack100vhCenter>
        );
    }

    const layout = publicAlbumLayout;
    const quickLinkDateRange = quickLinkDateRangeForFiles(publicFiles);
    const isQuickLinkAlbum =
        quickLinkDateRange !== undefined &&
        publicCollection?.name === quickLinkDateRange;
    const isSingleFileAlbum = publicFiles.length === 1;
    const shouldShowSingleFileViewer = isQuickLinkAlbum && isSingleFileAlbum;

    if (shouldShowSingleFileViewer) {
        return (
            <>
                <LazyPublicAlbumSingleFileViewer
                    file={publicFiles[0]!}
                    publicAlbumsCredentials={credentials.current}
                    collectionKey={collectionKey.current!}
                    enableDownload={downloadEnabled}
                    enableComment={commentsEnabled}
                    enableJoin={joinEnabled}
                    onJoinAlbum={handleJoinAlbum}
                    onVisualFeedback={handleVisualFeedback}
                    onAddSaveGroup={onAddSaveGroup}
                />
                {blockingLoad && <TranslucentLoadingOverlay />}
                <ActiveDownloadStatusNotifications fullWidthOnMobile />
            </>
        );
    }

    const content = (
        <>
            {layout === "trip" ? (
                <LazyTripLayout
                    files={publicFiles}
                    collection={publicCollection}
                    onAddPhotos={onAddPhotos}
                    enableDownload={downloadEnabled}
                    accessToken={credentials.current.accessToken}
                    collectionKey={collectionKey.current}
                    credentials={credentials}
                    enableComment={commentsEnabled}
                    enableJoin={joinEnabled}
                />
            ) : (
                <>
                    <NavbarBase
                        sx={[
                            {
                                flex: "0 0 60px",
                                px: "24px",
                                "@media (width < 720px)": {
                                    px: "12px",
                                    ...(showMobileMasonryCover
                                        ? { borderBottom: "none" }
                                        : {}),
                                },
                            },
                            selected.count > 0 && {
                                borderColor: "accent.main",
                                overflowX: "hidden",
                            },
                        ]}
                    >
                        {selected.count > 0 ? (
                            <SelectedFileOptions
                                count={selected.count}
                                clearSelection={clearSelection}
                                downloadFilesHelper={downloadFilesHelper}
                            />
                        ) : (
                            <SpacedRow sx={{ flex: 1 }}>
                                <EnteLogoLink href="https://ente.com">
                                    <EnteLogo height={17} />
                                </EnteLogoLink>
                                <Stack direction="row" spacing={2}>
                                    <SecondaryActionButton
                                        onAddPhotos={onAddPhotos}
                                        addPhotosDisabled={isUploadInProgress}
                                        enableJoin={joinEnabled}
                                        onJoinAlbum={handleJoinAlbum}
                                    />
                                    <PrimaryActionButton />
                                </Stack>
                            </SpacedRow>
                        )}
                    </NavbarBase>
                    <FileListWithViewer
                        files={publicFiles}
                        layout={layout === "masonry" ? "masonry" : "grid"}
                        header={fileListHeader}
                        footer={fileListFooter}
                        enableDownload={downloadEnabled}
                        enableSelect={downloadEnabled}
                        selected={selected}
                        setSelected={setSelected}
                        activeCollectionID={publicAlbumAllFilesCollectionID}
                        emptyStateAction={emptyStateAction}
                        onAddSaveGroup={onAddSaveGroup}
                        publicAlbumsCredentials={credentials.current}
                        collectionKey={collectionKey.current}
                        onJoinAlbum={handleJoinAlbum}
                        enableComment={commentsEnabled}
                        enableJoin={joinEnabled}
                        pendingFileIndex={pendingFileNavigation?.fileIndex}
                        pendingFileSidebar={pendingFileNavigation?.sidebar}
                        pendingHighlightCommentID={
                            pendingFileNavigation?.commentID
                        }
                        pendingAnonUserNames={
                            pendingFileNavigation?.anonUserNames
                        }
                        onPendingNavigationConsumed={() =>
                            setPendingFileNavigation(undefined)
                        }
                    />
                </>
            )}
            {blockingLoad && <TranslucentLoadingOverlay />}
            {collectEnabled && shouldRenderUpload && (
                <LazyUpload
                    publicAlbumsCredentials={credentials.current}
                    uploadCollection={publicCollection}
                    setLoading={setBlockingLoad}
                    setShouldDisableDropzone={setShouldDisableDropzone}
                    uploadTypeSelectorView={uploadTypeSelectorView}
                    onRemotePull={publicAlbumsRemotePull}
                    onUploadFile={handleUploadFile}
                    closeUploadTypeSelector={closeUploadTypeSelectorView}
                    onShowSessionExpiredDialog={showPublicLinkExpiredMessage}
                    onUploadInProgressChange={setIsUploadInProgress}
                    {...{ dragAndDropFiles }}
                />
            )}
            <ActiveDownloadStatusNotifications fullWidthOnMobile />
            {(publicFeedVisibilityProps.open || keepPublicFeedSidebarMounted) &&
                publicCollection &&
                collectionKey.current && (
                    <LazyPublicFeedSidebar
                        {...publicFeedVisibilityProps}
                        files={publicFiles}
                        credentials={credentials.current}
                        collectionKey={collectionKey.current}
                        onItemClick={handleFeedItemClick}
                        onExited={handlePublicFeedSidebarExited}
                    />
                )}
        </>
    );

    return (
        <LazyCollectDropZone
            enabled={collectEnabled}
            disabled={shouldDisableDropzone}
            onDrop={handleDrop}
            message={t("upload_dropzone_hint_public_album")}
        >
            {content}
        </LazyCollectDropZone>
    );
}

/**
 * Sort the given {@link files} using {@link sortFiles}, using the ascending
 * ordering preference if specified in the given {@link collection}'s metadata.
 */
const sortFilesForCollection = (files: EnteFile[], collection?: Collection) =>
    sortFiles(files, collection?.pubMagicMetadata?.data.asc ?? false);

type PublicAlbumLayout = "masonry" | "grouped" | "trip";

const normalizedPublicAlbumLayout = (
    layout: string | undefined,
): PublicAlbumLayout => {
    if (layout === "continuous") {
        return "masonry";
    }
    if (layout === "grouped" || layout === "trip" || layout === "masonry") {
        return layout;
    }
    return "masonry";
};

const useViewportWidth = () => {
    const [viewportWidth, setViewportWidth] = useState<number | undefined>(
        undefined,
    );

    useEffect(() => {
        if (typeof window === "undefined") return;

        const update = () => setViewportWidth(window.innerWidth);
        update();

        window.addEventListener("resize", update);
        return () => window.removeEventListener("resize", update);
    }, []);

    return viewportWidth;
};

const mobileMasonryFileListHeaderHeight = (viewportWidth: number | undefined) =>
    Math.round(mobileMasonryCoverHeight(viewportWidth) + thumbnailGap);

const mobileMasonryCoverHeight = (viewportWidth: number | undefined) => {
    const width = Math.max(320, Math.min(viewportWidth ?? 390, 719));
    const coverWidth = width - 2 * 4;
    return coverWidth * (4 / 3);
};

const publicAlbumCoverFile = (
    collection: Collection,
    files: EnteFile[],
): EnteFile | undefined => {
    const coverID = collection.pubMagicMetadata?.data.coverID;
    if (typeof coverID === "number" && coverID > 0) {
        const explicitCover = files.find((file) => file.id === coverID);
        if (explicitCover) return explicitCover;
    }

    const preferredFiles = files.filter(
        (file) =>
            file.metadata.fileType !== FileType.video &&
            !file.metadata.hasStaticThumbnail,
    );
    const fallbackFiles =
        preferredFiles.length > 0
            ? preferredFiles
            : files.filter((file) => !file.metadata.hasStaticThumbnail);
    const coverCandidates = fallbackFiles.length > 0 ? fallbackFiles : files;

    return deterministicAlbumCoverFile(collection.id, coverCandidates);
};

const deterministicAlbumCoverFile = (
    seed: number,
    files: EnteFile[],
): EnteFile | undefined => {
    let coverFile: EnteFile | undefined;
    let highestRank = Number.NEGATIVE_INFINITY;

    for (const file of files) {
        const rank = deterministicCoverRank(seed, file.id);
        if (rank > highestRank) {
            highestRank = rank;
            coverFile = file;
        }
    }

    return coverFile;
};

const deterministicCoverRank = (seed: number, value: number) => {
    let x = (seed ^ value) >>> 0;
    x = Math.imul(x ^ (x >>> 16), 2246822507);
    x = Math.imul(x ^ (x >>> 13), 3266489909);
    return (x ^ (x >>> 16)) >>> 0;
};

type LazyCollectDropZoneProps = PropsWithChildren<
    { enabled: boolean } & Pick<
        FullScreenDropZoneProps,
        "disabled" | "message" | "onDrop"
    >
>;

const LazyCollectDropZone: React.FC<LazyCollectDropZoneProps> = ({
    enabled,
    children,
    ...props
}) => {
    const [DropZoneComponent, setDropZoneComponent] = useState<ComponentType<
        PropsWithChildren<FullScreenDropZoneProps>
    > | null>(null);

    useEffect(() => {
        if (!enabled || DropZoneComponent) return;

        let isCancelled = false;
        void import("ente-gallery/components/FullScreenDropZone").then(
            ({ FullScreenDropZone }) => {
                if (isCancelled) return;
                setDropZoneComponent(() => FullScreenDropZone);
            },
        );

        return () => {
            isCancelled = true;
        };
    }, [DropZoneComponent, enabled]);

    if (!enabled || !DropZoneComponent) {
        return <>{children}</>;
    }

    return <DropZoneComponent {...props}>{children}</DropZoneComponent>;
};

const EnteLogoLink = styled("a")(({ theme }) => ({
    // Remove the excess space at the top.
    svg: { verticalAlign: "middle" },
    color: theme.vars.palette.text.base,
    ":hover": { color: theme.vars.palette.accent.main },
}));

const GreenButton = styled(Button)(() => ({
    backgroundColor: "#08C225",
    borderRadius: "16px",
    paddingBlock: "11px",
    paddingInline: "20px",
    "&:hover": { backgroundColor: "#07A820" },
}));

const navbarActionButtonSx = { borderRadius: "16px", paddingBlock: "11px" };

const PrimaryActionButton: React.FC = () => {
    const handleGetEnte = () => {
        window.location.href = getEnteURL();
    };

    return (
        <GreenButton color="accent" onClick={handleGetEnte}>
            {t("join_ente")}
        </GreenButton>
    );
};

interface SecondaryActionButtonProps {
    onAddPhotos?: () => void;
    addPhotosDisabled?: boolean;
    enableJoin?: boolean;
    onJoinAlbum?: () => void;
}

const SecondaryActionButton: React.FC<SecondaryActionButtonProps> = ({
    onAddPhotos,
    addPhotosDisabled,
    enableJoin,
    onJoinAlbum,
}) => {
    if (onAddPhotos) {
        return (
            <FocusVisibleButton
                color="secondary"
                sx={navbarActionButtonSx}
                onClick={onAddPhotos}
                disabled={addPhotosDisabled}
            >
                {t("upload")}
            </FocusVisibleButton>
        );
    }

    if (enableJoin) {
        return (
            <FocusVisibleButton
                color="secondary"
                sx={navbarActionButtonSx}
                onClick={onJoinAlbum}
            >
                {t("join_album")}
            </FocusVisibleButton>
        );
    }

    return null;
};

interface SelectedFileOptionsProps {
    count: number;
    clearSelection: () => void;
    downloadFilesHelper: () => void;
}

const SelectedFileOptions: React.FC<SelectedFileOptionsProps> = ({
    count,
    clearSelection,
    downloadFilesHelper,
}) => (
    <Stack
        direction="row"
        sx={{
            flex: 1,
            minWidth: 0,
            gap: 1,
            alignItems: "center",
            width: "100%",
        }}
    >
        <IconButton
            onClick={clearSelection}
            sx={{ flexShrink: 0, ml: "-15px" }}
        >
            <CloseIcon />
        </IconButton>
        <Typography
            sx={{
                mr: "auto",
                minWidth: 0,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
            }}
        >
            {t("selected_count", { selected: count })}
        </Typography>
        <Tooltip title={t("download")}>
            <IconButton
                onClick={downloadFilesHelper}
                sx={{ flexShrink: 0, mr: "-15px" }}
            >
                <DownloadIcon size={24} />
            </IconButton>
        </Tooltip>
    </Stack>
);

interface FileListHeaderProps {
    publicCollection: Collection;
    publicFiles: EnteFile[];
    downloadEnabled: boolean;
    onAddSaveGroup: AddSaveGroup;
    onAddPhotos?: () => void;
    onShowFeed?: () => void;
    addPhotosDisabled: boolean;
    hasSelection: boolean;
    showMobileMasonryCover: boolean;
}

/**
 * The fixed height (in px) of {@link FileListHeader}.
 */
const fileListHeaderHeight = 84;

/**
 * The height (in px) of {@link FileListHeader} on mobile.
 *
 * Keep this fixed so the virtualized list has a stable header row height.
 */
const fileListHeaderHeightMobile = 132;

/**
 * A header shown before the listing of files.
 *
 * It scrolls along with the content. It has a fixed height,
 * {@link fileListHeaderHeight}.
 */
const FileListHeader: React.FC<FileListHeaderProps> = ({
    publicCollection,
    publicFiles,
    downloadEnabled,
    onAddSaveGroup,
    onAddPhotos,
    onShowFeed,
    addPhotosDisabled,
    hasSelection,
    showMobileMasonryCover,
}) => {
    const [showCopiedMessage, setShowCopiedMessage] = useState(false);

    const memoriesDateRange = useMemo(() => {
        return quickLinkDateRangeForFiles(publicFiles);
    }, [publicFiles]);

    const coverFile = useMemo(
        () => publicAlbumCoverFile(publicCollection, publicFiles),
        [publicCollection, publicFiles],
    );

    const isQuickLinkAlbum =
        memoriesDateRange !== undefined &&
        publicCollection.name === memoriesDateRange;

    const downloadAllFiles = () => {
        void import("@/public-album/download/services/save").then(
            ({ downloadAndSaveCollectionFiles }) =>
                downloadAndSaveCollectionFiles(
                    publicCollection.name,
                    publicCollection.id,
                    publicFiles,
                    undefined,
                    onAddSaveGroup,
                ),
        );
    };

    const handleShare = async () => {
        if (typeof window === "undefined") return;

        const shareUrl = window.location.href;
        const shareText = `${publicCollection.name}\n${shareUrl}`;
        const isMobile = window.matchMedia("(width < 720px)").matches;

        if (isMobile && typeof navigator.share === "function") {
            try {
                await navigator.share({ text: shareText });
                return;
            } catch (error) {
                if (error instanceof Error && error.name === "AbortError") {
                    return;
                }
            }
        }

        void navigator.clipboard.writeText(isMobile ? shareText : shareUrl);
        setShowCopiedMessage(true);
        setTimeout(() => setShowCopiedMessage(false), 2000);
    };

    const actions = (
        <FileListHeaderActions
            onShowFeed={onShowFeed}
            downloadEnabled={downloadEnabled}
            onDownloadAll={downloadAllFiles}
            onAddPhotos={onAddPhotos}
            addPhotosDisabled={addPhotosDisabled}
            hasSelection={hasSelection}
            onShare={handleShare}
            align={showMobileMasonryCover ? "start" : "end"}
        />
    );

    const coverActions = (
        <FileListHeaderActions
            onShowFeed={onShowFeed}
            downloadEnabled={downloadEnabled}
            onDownloadAll={downloadAllFiles}
            onAddPhotos={onAddPhotos}
            addPhotosDisabled={addPhotosDisabled}
            hasSelection={hasSelection}
            onShare={handleShare}
            align="center"
            variant="cover"
        />
    );

    return (
        <>
            {showMobileMasonryCover ? (
                <GalleryItemsHeaderAdapter
                    sx={{ pt: 0, mb: `${thumbnailGap}px` }}
                >
                    <PublicAlbumCoverHero
                        coverFile={coverFile}
                        title={publicCollection.name}
                        fileCount={publicFiles.length}
                        dateRange={
                            isQuickLinkAlbum ? undefined : memoriesDateRange
                        }
                        actions={coverActions}
                    />
                </GalleryItemsHeaderAdapter>
            ) : (
                <GalleryItemsHeaderAdapter sx={{ pt: "16px" }}>
                    <SpacedRow
                        sx={{
                            width: "100%",
                            "@media (width < 720px)": {
                                flexDirection: "column",
                                alignItems: "flex-start",
                                gap: 1,
                            },
                        }}
                    >
                        <Box
                            sx={{
                                minWidth: 0,
                                flex: 1,
                                "@media (width < 720px)": { width: "100%" },
                            }}
                        >
                            <GalleryItemsSummary
                                name={publicCollection.name}
                                fileCount={publicFiles.length}
                                endIcon={
                                    !isQuickLinkAlbum && memoriesDateRange ? (
                                        <Typography
                                            variant="small"
                                            sx={{
                                                color: "text.muted",
                                                ml: "-6px",
                                            }}
                                        >
                                            <Box
                                                component="span"
                                                sx={{ mr: "6px" }}
                                            >
                                                {"\u00b7"}
                                            </Box>
                                            {memoriesDateRange}
                                        </Typography>
                                    ) : undefined
                                }
                                nameProps={{
                                    noWrap: true,
                                    sx: { width: "100%", maxWidth: "100%" },
                                }}
                            />
                        </Box>
                        {actions}
                    </SpacedRow>
                </GalleryItemsHeaderAdapter>
            )}
            {showCopiedMessage && (
                <LazyNotification
                    open={showCopiedMessage}
                    onClose={() => setShowCopiedMessage(false)}
                    horizontal="left"
                    attributes={{
                        color: "secondary",
                        startIcon: <CheckIcon />,
                        title: "Copied!",
                    }}
                />
            )}
        </>
    );
};

interface FileListHeaderActionsProps {
    onShowFeed?: () => void;
    downloadEnabled: boolean;
    onDownloadAll: () => void;
    onAddPhotos?: () => void;
    addPhotosDisabled: boolean;
    hasSelection: boolean;
    onShare: () => void;
    align: "start" | "end" | "center";
    variant?: "default" | "cover";
}

const FileListHeaderActions: React.FC<FileListHeaderActionsProps> = ({
    onShowFeed,
    downloadEnabled,
    onDownloadAll,
    onAddPhotos,
    addPhotosDisabled,
    hasSelection,
    onShare,
    align,
    variant = "default",
}) => (
    <Stack
        direction="row"
        spacing={0}
        sx={{
            width: align === "end" ? "auto" : "100%",
            alignItems: "center",
            justifyContent:
                align === "start"
                    ? "flex-start"
                    : align === "center"
                      ? "center"
                      : "flex-end",
            ...(variant === "default"
                ? {
                      "@media (width > 720px)":
                          align === "end" ? { mr: -1.5 } : {},
                      "@media (width < 720px)": { ml: -1.5 },
                  }
                : { gap: 0.75, flexWrap: "wrap" }),
        }}
    >
        {onShowFeed && (
            <IconButton
                onClick={onShowFeed}
                disabled={hasSelection}
                sx={actionButtonSx(variant)}
            >
                <FeedIcon size={24} />
            </IconButton>
        )}
        {downloadEnabled && (
            <IconButton
                onClick={onDownloadAll}
                disabled={hasSelection}
                sx={actionButtonSx(variant)}
            >
                <DownloadIcon size={24} />
            </IconButton>
        )}
        {onAddPhotos && (
            <IconButton
                onClick={onAddPhotos}
                disabled={addPhotosDisabled || hasSelection}
                sx={actionButtonSx(variant)}
            >
                <AddPhotosIcon size={24} />
            </IconButton>
        )}
        <IconButton
            onClick={onShare}
            disabled={hasSelection}
            sx={actionButtonSx(variant)}
        >
            <ShareIcon size={24} />
        </IconButton>
    </Stack>
);

const actionButtonSx = (variant: "default" | "cover") =>
    variant === "cover"
        ? {
              width: 46,
              height: 46,
              color: "common.white",
              backgroundColor: "rgba(0, 0, 0, 0.5)",
              "& svg": { color: "inherit" },
              "&:hover": { backgroundColor: "rgba(0, 0, 0, 0.5)" },
              "&.Mui-disabled": {
                  color: "rgba(255, 255, 255, 0.38)",
                  backgroundColor: "rgba(0, 0, 0, 0.28)",
              },
          }
        : undefined;

interface PublicAlbumCoverHeroProps {
    coverFile: EnteFile | undefined;
    title: string;
    fileCount: number;
    dateRange?: string;
    actions?: React.ReactNode;
}

const PublicAlbumCoverHero: React.FC<PublicAlbumCoverHeroProps> = ({
    coverFile,
    title,
    fileCount,
    dateRange,
    actions,
}) => {
    const [thumbnailURL, setThumbnailURL] = useState<string | undefined>();
    const [fullImageURL, setFullImageURL] = useState<string | undefined>();
    const coverRequestIDRef = useRef(0);

    useEffect(() => {
        const requestID = ++coverRequestIDRef.current;

        setThumbnailURL(undefined);
        setFullImageURL(undefined);

        if (!coverFile || coverFile.metadata.hasStaticThumbnail) {
            return undefined;
        }

        const loadThumbnail = async () => {
            const setThumbnailURLIfCurrent = (url: string | undefined) => {
                if (requestID === coverRequestIDRef.current && url) {
                    setThumbnailURL(url);
                    return true;
                }
                return false;
            };

            let didSetThumbnail: boolean;
            try {
                const cachedURL = await thumbnailManager.renderableThumbnailURL(
                    coverFile,
                    true,
                );
                didSetThumbnail = setThumbnailURLIfCurrent(cachedURL);
                if (
                    !didSetThumbnail &&
                    requestID !== coverRequestIDRef.current
                ) {
                    return;
                }

                if (!didSetThumbnail) {
                    const remoteURL =
                        await thumbnailManager.renderableThumbnailURL(
                            coverFile,
                        );
                    didSetThumbnail = setThumbnailURLIfCurrent(remoteURL);
                }
            } catch (e) {
                log.warn("Failed to fetch public album cover thumbnail", e);
                return;
            }

            if (
                !didSetThumbnail ||
                !isFullQualityCoverSourceSupported(coverFile)
            ) {
                return;
            }

            try {
                const sourceURLs =
                    await downloadManager.renderableSourceURLs(coverFile);
                const sourceURL =
                    sourceURLs.type === "image"
                        ? sourceURLs.imageURL
                        : sourceURLs.type === "livePhoto"
                          ? await sourceURLs.imageURL()
                          : undefined;
                if (!sourceURL || requestID !== coverRequestIDRef.current) {
                    return;
                }

                await preloadImage(sourceURL);
                if (requestID === coverRequestIDRef.current) {
                    setFullImageURL(sourceURL);
                }
            } catch (e) {
                log.warn("Failed to fetch full quality public album cover", e);
            }
        };

        void loadThumbnail();

        return () => {
            coverRequestIDRef.current = requestID + 1;
        };
    }, [coverFile]);

    const isPlaceholder =
        !coverFile || coverFile.metadata.hasStaticThumbnail || !thumbnailURL;

    return (
        <MobileMasonryCover $isPlaceholder={isPlaceholder}>
            {coverFile?.metadata.hasStaticThumbnail ? (
                <StaticThumbnail fileType={coverFile.metadata.fileType} />
            ) : thumbnailURL ? (
                <>
                    <MobileMasonryCoverPreviewImage
                        src={thumbnailURL}
                        alt={title}
                        decoding="async"
                        loading="eager"
                        fetchPriority="high"
                    />
                    {fullImageURL && fullImageURL !== thumbnailURL && (
                        <MobileMasonryCoverFullImage
                            src={fullImageURL}
                            alt=""
                            aria-hidden
                            decoding="async"
                            loading="eager"
                        />
                    )}
                </>
            ) : (
                <LoadingThumbnail />
            )}
            <MobileMasonryCoverGradient $isPlaceholder={isPlaceholder} />
            <MobileMasonryCoverContent>
                <MobileMasonryCoverTitle>{title}</MobileMasonryCoverTitle>
                <Typography
                    variant="small"
                    sx={{
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        flexWrap: "wrap",
                        gap: "6px",
                        fontSize: "16px",
                        lineHeight: 1.2,
                        minWidth: 0,
                    }}
                >
                    <Box component="span" sx={{ opacity: 0.72, flexShrink: 0 }}>
                        {t("photos_count", { count: fileCount })}
                    </Box>
                    {dateRange && (
                        <Box
                            component="span"
                            sx={{
                                opacity: 0.72,
                                display: "inline-flex",
                                alignItems: "center",
                                minWidth: 0,
                            }}
                        >
                            <Box
                                component="span"
                                sx={{ flexShrink: 0, mr: "6px" }}
                            >
                                {"\u00b7"}
                            </Box>
                            <Box
                                component="span"
                                sx={{
                                    minWidth: 0,
                                    overflow: "hidden",
                                    textOverflow: "ellipsis",
                                    whiteSpace: "nowrap",
                                }}
                            >
                                {dateRange}
                            </Box>
                        </Box>
                    )}
                </Typography>
                {actions}
            </MobileMasonryCoverContent>
        </MobileMasonryCover>
    );
};

const isFullQualityCoverSourceSupported = (file: EnteFile) =>
    file.metadata.fileType === FileType.image ||
    file.metadata.fileType === FileType.livePhoto;

const preloadImage = async (url: string) => {
    const image = new Image();
    image.decoding = "async";
    const loadPromise = new Promise<void>((resolve, reject) => {
        image.onload = () => resolve();
        image.onerror = reject;
    });
    image.src = url;
    await loadPromise;
    await image.decode().catch(() => undefined);
};

const mobileMasonryCoverImageGradient =
    "linear-gradient(to bottom, rgba(0, 0, 0, 0.08), rgba(0, 0, 0, 0.18) 42%, rgba(0, 0, 0, 0.74) 100%)";

const mobileMasonryCoverPlaceholderGradient =
    "linear-gradient(to bottom, rgba(0, 0, 0, 0.02), rgba(0, 0, 0, 0.08) 42%, rgba(0, 0, 0, 0.42) 100%)";

const MobileMasonryCover = styled(Box, {
    shouldForwardProp: (prop) => prop !== "$isPlaceholder",
})<{ $isPlaceholder: boolean }>(({ theme, $isPlaceholder }) => ({
    position: "relative",
    overflow: "hidden",
    borderRadius: "4px",
    aspectRatio: "3 / 4",
    backgroundColor: $isPlaceholder ? "#F4F4F4" : "#1b1b1b",
    "& > img": {
        position: "absolute",
        inset: 0,
        width: "100%",
        height: "100%",
        objectFit: "cover",
    },
    ...theme.applyStyles("dark", { backgroundColor: "#1b1b1b" }),
}));

const MobileMasonryCoverPreviewImage = styled("img")({
    filter: "blur(3px) saturate(1.08) brightness(0.94)",
});

const MobileMasonryCoverFullImage = styled("img")({
    animation: "mobile-masonry-cover-reveal 420ms ease-out both",
    "@keyframes mobile-masonry-cover-reveal": {
        from: { opacity: 0 },
        to: { opacity: 1 },
    },
});

const MobileMasonryCoverGradient = styled(Box, {
    shouldForwardProp: (prop) => prop !== "$isPlaceholder",
})<{ $isPlaceholder: boolean }>(({ theme, $isPlaceholder }) => ({
    position: "absolute",
    inset: 0,
    background: $isPlaceholder
        ? mobileMasonryCoverPlaceholderGradient
        : mobileMasonryCoverImageGradient,
    ...theme.applyStyles("dark", {
        background: mobileMasonryCoverImageGradient,
    }),
}));

const MobileMasonryCoverContent = styled(Box)({
    position: "absolute",
    inset: 0,
    display: "flex",
    flexDirection: "column",
    justifyContent: "flex-end",
    alignItems: "center",
    textAlign: "center",
    gap: "14px",
    padding: "18px 18px 32px",
    color: "white",
});

const MobileMasonryCoverTitle = styled(Typography)({
    fontSize: "36px",
    fontWeight: 600,
    lineHeight: 1.2,
    letterSpacing: "-0.03em",
    textAlign: "center",
    width: "100%",
    maxWidth: "100%",
    overflowWrap: "anywhere",
});

/**
 * The default height (in px) of {@link FileListFooter}.
 */
const fileListFooterHeight = 24;

/**
 * The compact trailing gap used after the final photo in the mobile masonry
 * cover layout.
 */
const mobileMasonryFileListFooterHeight = thumbnailGap;

/**
 * A footer shown after the listing of files.
 *
 * It scrolls along with the content.
 */
const FileListFooter: React.FC<{ height: number }> = ({ height }) => (
    <Box sx={{ height }} />
);
