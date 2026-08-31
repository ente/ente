import { isNamedError } from "ente-base/error";
import log from "ente-base/log";
import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import "hls-video-element";
import { t } from "i18next";
import "media-chrome";
import { MediaMuteButton } from "media-chrome";
import "media-chrome/menu";
import { MediaChromeMenu, MediaChromeMenuButton } from "media-chrome/menu";
import PhotoSwipe, { type SlideData } from "photoswipe";
import type { ItemData, ItemDataOpts } from "./data-source-core";
import {
    commentSVGPath,
    createPSRegisterElementIconHTML,
    heartFillSVGPath,
    heartSVGPath,
    settingsSVGPath,
} from "./icons";

export interface FileViewerPhotoSwipeAnnotatedFile {
    file: EnteFile;
    annotation: {
        showFavorite: boolean;
        showDownload: "bar" | "menu" | undefined;
    };
    itemData: ItemData;
}

export interface FileViewerPhotoSwipeDataSource {
    fileViewerDidClose: () => void;
    fileViewerWillOpen: () => void;
    forgetExifForItemData: (itemData: ItemData) => void;
    forgetItemDataForFileID: (fileID: number) => void;
    forgetItemDataForFileIDIfNeeded: (fileID: number) => void;
    itemDataForFile: (
        file: EnteFile,
        opts: ItemDataOpts | undefined,
        needsRefresh: () => void,
    ) => ItemData;
    updateFileInfoExifIfNeeded: (itemData: ItemData) => Promise<void>;
}

export interface FileViewerPhotoSwipeDelegate<
    T extends FileViewerPhotoSwipeAnnotatedFile =
        FileViewerPhotoSwipeAnnotatedFile,
> {
    getFiles: () => EnteFile[];
    isFavorite: (annotatedFile: T) => boolean | undefined;
    isFavoritePending: (annotatedFile: T) => boolean;
    // Handle foreseeable failures here; rejection leaves the button disabled.
    toggleFavorite: (annotatedFile: T) => Promise<void>;
    isLiked: (annotatedFile: T) => boolean;
    getCommentCount: (annotatedFile: T) => number;
    shouldShowSocialButtons: (annotatedFile: T) => boolean;
    shouldIgnoreKeyboardEvent: (event: KeyboardEvent) => boolean;
    performKeyAction: (
        action:
            | "delete"
            | "toggle-archive"
            | "copy"
            | "toggle-fullscreen"
            | "help",
    ) => void;
}

export interface FileViewerPhotoSwipeCoreOptions<
    T extends FileViewerPhotoSwipeAnnotatedFile =
        FileViewerPhotoSwipeAnnotatedFile,
> {
    initialIndex: number;
    showFullscreenButton?: boolean;
    disableEscapeClose?: boolean;
    disableGestureClose?: boolean;
    dataSource: FileViewerPhotoSwipeDataSource;
    haveUser: boolean;
    isPublicAlbum?: boolean;
    publicAlbumLogoHTML?: string;
    showSocialButtons: boolean;
    enableComment: boolean;
    delegate: FileViewerPhotoSwipeDelegate<T>;
    onClose: () => void;
    onAnnotate: (file: EnteFile, itemData: ItemData) => T;
    onViewInfo: (annotatedFile: T) => void;
    onViewComments: () => void;
    onViewLikes: () => void;
    onLikeClick: () => void;
    onDownload: (annotatedFile: T) => void;
    onMore: (buttonElement: HTMLElement) => void;
}

export const moreButtonID = "ente-pswp-more-button";

export const moreMenuID = "ente-pswp-more-menu";

const fullscreenControlsAutoHideDelayMS = 3000;

export class FileViewerPhotoSwipe<
    T extends FileViewerPhotoSwipeAnnotatedFile =
        FileViewerPhotoSwipeAnnotatedFile,
> {
    private pswp: PhotoSwipe;

    constructor({
        initialIndex,
        haveUser,
        isPublicAlbum,
        publicAlbumLogoHTML,
        showSocialButtons,
        enableComment,
        showFullscreenButton,
        disableEscapeClose,
        disableGestureClose,
        dataSource,
        delegate,
        onClose,
        onAnnotate,
        onViewInfo,
        onViewComments,
        onViewLikes,
        onLikeClick,
        onDownload,
        onMore,
    }: FileViewerPhotoSwipeCoreOptions<T>) {
        const pswp = new PhotoSwipe({
            bgOpacity: 1,
            showHideAnimationType: "fade",
            // PhotoSwipe otherwise closes a loaded thumbnail that cannot zoom.
            clickToCloseNonZoomable: false,
            // The background boundary is ambiguous, so taps only toggle controls.
            bgClickAction: "toggle-controls",
            escKey: !disableEscapeClose,
            pinchToClose: !disableGestureClose,
            closeOnVerticalDrag: !disableGestureClose,
            wheelToZoom: true,
            // PhotoSwipe's focus trap conflicts with MUI drawers and fast swipes.
            trapFocus: false,
            index: initialIndex,
            mainClass: isPublicAlbum
                ? "pswp-ente pswp-ente-public-album"
                : "pswp-ente",
            closeTitle: t("close"),
            zoomTitle: t("zoom"),
            arrowPrevTitle: t("previous"),
            arrowNextTitle: t("next"),
            errorMsg: t("unpreviewable_file_message"),
        });

        this.pswp = pswp;

        let _currentAnnotatedFile: T | undefined;

        const asItemData = (slideData: SlideData | undefined) =>
            slideData! as ItemData;

        const currSlideData = () => asItemData(pswp.currSlide?.data);

        const currentFile = () => delegate.getFiles()[pswp.currIndex]!;

        const currentAnnotatedFile = (): T => {
            const file = currentFile();
            let annotatedFile = _currentAnnotatedFile;
            if (
                annotatedFile?.file.id != file.id ||
                annotatedFile.file.updationTime != file.updationTime
            ) {
                const slideData = pswp.currSlide?.data as ItemData | undefined;
                if (slideData) {
                    annotatedFile = onAnnotate(file, slideData);
                    _currentAnnotatedFile = annotatedFile;
                }
            }
            return annotatedFile!;
        };

        const currentFileAnnotation = () => currentAnnotatedFile().annotation;

        // Refreshing slide content resets pan and zoom, so only do it when needed.
        this.refreshSlideOnFilesUpdateIfNeeded = () => {
            const prevFileID = _currentAnnotatedFile?.file.id;
            if (!prevFileID) return;

            const files = delegate.getFiles();
            const newFileCount = files.length;

            const newFile = files[pswp.currIndex];
            if (newFile?.id != prevFileID) {
                const newIndex = files.findIndex(({ id }) => id == prevFileID);

                if (newIndex == -1) {
                    const i = pswp.currIndex;

                    if (i >= newFileCount) {
                        this.pswp.prev();
                    }

                    // The preloaded neighbour otherwise repeats the newly current file.
                    pswp.refreshSlideContent(i);
                    pswp.refreshSlideContent(i + 1 == newFileCount ? 0 : i + 1);
                } else {
                    const i = newIndex;

                    pswp.goTo(i);
                    pswp.refreshSlideContent(i == 0 ? newFileCount - 1 : i - 1);
                    pswp.refreshSlideContent(i + 1 == newFileCount ? 0 : i + 1);
                }
            } else {
                currentAnnotatedFile();
            }
        };

        const originalVideoFileIDs = new Set<number>();

        const intendedVideoQualityForFileID = (fileID: number) =>
            originalVideoFileIDs.has(fileID) ? "original" : "auto";

        pswp.addFilter("numItems", () => delegate.getFiles().length);

        pswp.addFilter("itemData", (_, index) => {
            const files = delegate.getFiles();
            const file = files[index]!;

            const videoQuality = intendedVideoQualityForFileID(file.id);

            const itemData = dataSource.itemDataForFile(
                file,
                { videoQuality },
                () => {
                    _currentAnnotatedFile = undefined;
                    pswp.refreshSlideContent(index);
                },
            );

            if (itemData.fileType == FileType.video) {
                const { videoPlaylistURL, videoURL } = itemData;
                if (videoPlaylistURL && videoQuality == "auto") {
                    const mcID = `ente-mc-hls-${file.id}`;
                    return {
                        ...itemData,
                        html: hlsVideoHTML(videoPlaylistURL, mcID),
                        mediaControllerID: mcID,
                    };
                } else if (videoURL) {
                    const mcID = `ente-mc-orig-${file.id}`;
                    return {
                        ...itemData,
                        html: videoHTML(videoURL, mcID),
                        mediaControllerID: mcID,
                    };
                }
            }

            return itemData;
        });

        pswp.addFilter("isContentLoading", (isLoading, content) => {
            return asItemData(content.data).isContentLoading ?? isLoading;
        });

        pswp.addFilter("isContentZoomable", (isZoomable, content) => {
            return asItemData(content.data).isContentZoomable ?? isZoomable;
        });

        // This also prevents image decoding from replaying a live photo.
        const livePhotoInitialVisitedFileIDs = new Set<number>();

        let livePhotoPlayInitial = true;

        let livePhotoPlayInitialEndedEvent:
            | { listener: () => void; video: HTMLVideoElement }
            | undefined;

        let livePhotoMute = true;

        let livePhotoPlayButtonElement: HTMLElement | undefined;

        let livePhotoMuteButtonElement: HTMLElement | undefined;

        const livePhotoUpdatePlayInitial = (video: HTMLVideoElement) => {
            livePhotoUpdateUIState(video);

            const currFileID = currSlideData().fileID;
            if (livePhotoInitialVisitedFileIDs.has(currFileID)) {
                return;
            }

            livePhotoInitialVisitedFileIDs.add(currFileID);

            video.removeAttribute("loop");

            if (livePhotoPlayInitialEndedEvent) {
                const { video, listener } = livePhotoPlayInitialEndedEvent;
                video.removeEventListener("ended", listener);
                livePhotoPlayInitialEndedEvent = undefined;
            }

            if (livePhotoPlayInitial) {
                video.currentTime = 0;
                void abortablePlayVideo(video);
                video.style.display = "initial";
                const listener = () => {
                    livePhotoPlayInitialEndedEvent = undefined;
                    livePhotoUpdateUIState(video);
                };
                livePhotoPlayInitialEndedEvent = { video, listener };
                video.addEventListener("ended", listener, { once: true });
            } else {
                video.pause();
            }

            livePhotoUpdateUIState(video);
        };

        const livePhotoUpdateUIState = (video: HTMLVideoElement) => {
            const button = livePhotoPlayButtonElement;
            if (button) showIf(button, true);

            if (video.paused || video.ended) {
                button?.classList.add("pswp-ente-off");
                video.style.display = "none";
            } else {
                button?.classList.remove("pswp-ente-off");
                video.style.display = "initial";
            }
        };

        const livePhotoUpdatePlayToggle = (video: HTMLVideoElement) => {
            if (video.paused || video.ended) {
                video.setAttribute("loop", "");

                livePhotoPlayInitial = true;

                video.currentTime = 0;
                void abortablePlayVideo(video);
            } else {
                video.removeAttribute("loop");

                if (livePhotoPlayInitialEndedEvent) {
                    livePhotoPlayInitial = false;

                    const { video, listener } = livePhotoPlayInitialEndedEvent;
                    video.removeEventListener("ended", listener);
                    livePhotoPlayInitialEndedEvent = undefined;
                }

                video.pause();
            }

            livePhotoUpdateUIState(video);
        };

        const abortablePlayVideo = async (videoElement: HTMLVideoElement) => {
            try {
                await videoElement.play();
            } catch (e) {
                if (
                    isNamedError(e, "AbortError") &&
                    e.message.startsWith("The play() request was interrupted")
                ) {
                    // Ignore.
                } else {
                    throw e;
                }
            }
        };

        const livePhotoUpdateMute = (video: HTMLVideoElement) => {
            const button = livePhotoMuteButtonElement;
            if (button) showIf(button, true);

            if (livePhotoMute) {
                button?.classList.add("pswp-ente-off");
                video.muted = true;
            } else {
                button?.classList.remove("pswp-ente-off");
                video.muted = false;
            }
        };

        const livePhotoTogglePlayIfPossible = () => {
            const buttonElement = livePhotoPlayButtonElement;
            const video = livePhotoVideoOnSlide(pswp.currSlide);
            if (!buttonElement || !video) return;

            livePhotoUpdatePlayToggle(video);
        };

        const livePhotoToggleMuteIfPossible = () => {
            const buttonElement = livePhotoMuteButtonElement;
            const video = livePhotoVideoOnSlide(pswp.currSlide);
            if (!buttonElement || !video) return;

            livePhotoMute = !livePhotoMute;
            livePhotoUpdateMute(video);
        };

        let mediaControlsContainerElement: HTMLElement | undefined;

        let shouldIgnoreNextVideoQualityChange = false;

        // Media Chrome does not reconnect its controls until the next tick on reopen.
        const updateVideoControlsAndPlayback = (itemData: ItemData) => {
            setTimeout(() => _updateVideoControlsAndPlayback(itemData), 0);
        };

        const handleFullscreenButtonClick = (e: Event) => {
            e.stopPropagation();
            e.preventDefault();
            if (document.fullscreenElement) {
                void document.exitFullscreen();
            } else {
                // Fullscreen the document so PhotoSwipe controls remain accessible.
                void document.body.requestFullscreen();
                pswp.element?.classList.add("pswp--video-fullscreen");
                document.addEventListener(
                    "mousemove",
                    handleMouseMoveInFullscreen,
                );
            }
        };

        let fullscreenUIControlsHideTimer:
            | ReturnType<typeof setTimeout>
            | undefined;

        let areFullscreenUIControlsHiddenByShortcut = false;

        const clearFullscreenUIControlsHideTimer = () => {
            if (fullscreenUIControlsHideTimer) {
                clearTimeout(fullscreenUIControlsHideTimer);
                fullscreenUIControlsHideTimer = undefined;
            }
        };

        const scheduleFullscreenUIControlsAutoHide = () => {
            clearFullscreenUIControlsHideTimer();
            fullscreenUIControlsHideTimer = setTimeout(() => {
                pswp.element?.classList.remove("pswp--ui-visible");
                fullscreenUIControlsHideTimer = undefined;
            }, fullscreenControlsAutoHideDelayMS);
        };

        const handleFullscreenMouseMove = () => {
            if (!document.fullscreenElement) return;
            if (areFullscreenUIControlsHiddenByShortcut) return;

            pswp.element?.classList.add("pswp--ui-visible");
            scheduleFullscreenUIControlsAutoHide();
        };

        const handleFullscreenChange = () => {
            if (document.fullscreenElement) {
                document.addEventListener(
                    "mousemove",
                    handleFullscreenMouseMove,
                );
                handleFullscreenMouseMove();
                return;
            }

            document.removeEventListener(
                "mousemove",
                handleFullscreenMouseMove,
            );
            clearFullscreenUIControlsHideTimer();
            areFullscreenUIControlsHiddenByShortcut = false;
            pswp.element?.classList.add("pswp--ui-visible");

            pswp.element?.classList.remove("pswp--video-fullscreen");
            pswp.element?.classList.remove("pswp--controls-visible");
            document.removeEventListener(
                "mousemove",
                handleMouseMoveInFullscreen,
            );
            if (hideVideoControlsTimer) {
                clearTimeout(hideVideoControlsTimer);
                hideVideoControlsTimer = undefined;
            }
        };

        let hideVideoControlsTimer: ReturnType<typeof setTimeout> | undefined;

        const handleMouseMoveInFullscreen = () => {
            pswp.element?.classList.add("pswp--controls-visible");

            if (hideVideoControlsTimer) {
                clearTimeout(hideVideoControlsTimer);
            }

            hideVideoControlsTimer = setTimeout(() => {
                pswp.element?.classList.remove("pswp--controls-visible");
                hideVideoControlsTimer = undefined;
            }, fullscreenControlsAutoHideDelayMS);
        };

        const _updateVideoControlsAndPlayback = (itemData: ItemData) => {
            const container = mediaControlsContainerElement;
            const showVideoControls =
                itemData.fileType == FileType.video && !itemData.fetchFailed;
            const areVideoControlsDisabled =
                showVideoControls &&
                (!!itemData.isContentLoading || !itemData.mediaControllerID);
            container?.classList.toggle(
                "pswp__media-controls--visible",
                showVideoControls,
            );
            container?.classList.toggle(
                "pswp__media-controls--disabled",
                areVideoControlsDisabled,
            );

            const controls =
                container?.querySelectorAll(
                    "media-control-bar, media-playback-rate-menu",
                ) ?? [];
            for (const control of controls) {
                const { mediaControllerID } = itemData;
                if (mediaControllerID) {
                    control.setAttribute("mediacontroller", mediaControllerID);
                } else {
                    control.removeAttribute("mediacontroller");
                }
            }

            const qualityMenu = container?.querySelector("#ente-quality-menu");
            if (qualityMenu instanceof MediaChromeMenu) {
                const { videoPlaylistURL, fileID } = itemData;

                const item = qualityMenu.radioGroupItems[0]!;
                let didChangeHide = false;
                if (item.hidden && videoPlaylistURL) {
                    didChangeHide = true;
                    item.hidden = false;
                } else if (!item.hidden && !videoPlaylistURL) {
                    didChangeHide = true;
                    item.hidden = true;
                }

                const value =
                    intendedVideoQualityForFileID(fileID) == "auto" &&
                    videoPlaylistURL
                        ? t("auto")
                        : t("original");
                if (qualityMenu.value != value) {
                    shouldIgnoreNextVideoQualityChange = true;
                    qualityMenu.value = value;
                } else {
                    if (didChangeHide) {
                        closeMediaChromeSettingsMenuIfOpen();
                    }
                }
            }

            const video = videoVideoEl;
            if (video?.paused && !video.ended) void video.play();
        };

        const toggleMediaChromeSettingsMenu = () => {
            const menuButton = document.querySelector(
                "media-settings-menu-button",
            );
            if (menuButton instanceof MediaChromeMenuButton) {
                menuButton.handleClick();

                // Media Chrome retains invisible focus; both blur passes are required.
                const blurAllFocused = () =>
                    document
                        .querySelectorAll(":focus")
                        .forEach((e) => e instanceof HTMLElement && e.blur());

                blurAllFocused();
                setTimeout(blurAllFocused, 0);
            }
        };

        const closeMediaChromeSettingsMenuIfOpen = () => {
            if (document.querySelector("media-settings-menu:not([hidden])"))
                toggleMediaChromeSettingsMenu();
        };

        pswp.on("contentAppend", (e) => {
            // PhotoSwipe can emit this later for content it already detached.
            if (!e.content.hasSlide) {
                log.debug(() => ["Ignoring stale contentAppend", e]);
                return;
            }

            const { fileID, fileType, videoURL } = asItemData(e.content.data);

            // Initial contentAppend can follow change, so wire controls here too.
            if (currSlideData().fileID == fileID) {
                updateVideoControlsAndPlayback(currSlideData());
            }

            if (fileType != FileType.livePhoto || !videoURL) {
                return;
            }

            const img = e.content.element!;
            const video = createElementFromHTMLString(
                livePhotoVideoHTML(videoURL),
            ) as HTMLVideoElement;
            const container = e.content.slide!.container;
            container.style = "position: relative";
            container.appendChild(video);
            video.style =
                "position: absolute; top: 0; left: 0; z-index: 1; pointer-events: none;";

            video.style.width = img.style.width;
            video.style.height = img.style.height;

            if (currSlideData().fileID == fileID) {
                livePhotoUpdatePlayInitial(video);
                livePhotoUpdateMute(video);
            }
        });

        const livePhotoVideoOnSlide = (slide: typeof pswp.currSlide) =>
            asItemData(slide?.data).fileType == FileType.livePhoto
                ? slide?.container.getElementsByTagName("video")[0]
                : undefined;

        pswp.on("imageSizeChange", ({ content, width, height }) => {
            const video = livePhotoVideoOnSlide(content.slide);
            if (!video) {
                return;
            }

            video.style.width = `${width}px`;
            video.style.height = `${height}px`;
        });

        const queryVideoElement = (element: HTMLElement | undefined) =>
            element?.querySelector<HTMLVideoElement>("video, hls-video");

        pswp.on("contentDeactivate", (e) => {
            const fileID = asItemData(e.content.data).fileID;
            if (fileID) dataSource.forgetItemDataForFileIDIfNeeded(fileID);

            const video = queryVideoElement(e.content.slide?.container);
            video?.pause();
        });

        pswp.on(
            "loadComplete",
            (e) =>
                void dataSource.updateFileInfoExifIfNeeded(
                    asItemData(e.content.data),
                ),
        );

        pswp.on(
            "change",
            () => void dataSource.updateFileInfoExifIfNeeded(currSlideData()),
        );

        pswp.on("contentDestroy", (e) =>
            dataSource.forgetExifForItemData(asItemData(e.content.data)),
        );

        let videoVideoEl: HTMLVideoElement | undefined;

        let lastSlideChangeEpochMilli = Date.now();

        pswp.on("change", () => {
            const itemData = currSlideData();

            pswp.mainScroll.itemHolders.forEach(({ el }) => {
                // aria-hidden alone does not remove hidden slides from tab order.
                if (el.getAttribute("aria-hidden") == "true") {
                    el.setAttribute("inert", "");
                } else {
                    el.removeAttribute("inert");
                }
            });

            if (itemData.fileType == FileType.video) {
                const contentElement = pswp.currSlide?.content.element;
                videoVideoEl = queryVideoElement(contentElement) ?? undefined;
            } else {
                videoVideoEl = undefined;
            }

            lastSlideChangeEpochMilli = Date.now();
        });

        const videoTogglePlayIfPossible = () => {
            const video = videoVideoEl;
            if (!video) return;

            if (video.paused || video.ended) {
                void video.play();
            } else {
                video.pause();
            }
        };

        // Go through Media Chrome so its persisted mute preference stays in sync.
        const videoToggleMuteIfPossible = () => {
            const muteButton = document.querySelector("media-mute-button");
            if (muteButton instanceof MediaMuteButton) muteButton.handleClick();
        };

        const handleViewInfo = () => onViewInfo(currentAnnotatedFile());

        let favoriteButtonElement: HTMLButtonElement | undefined;

        const toggleFavorite = () =>
            delegate.toggleFavorite(currentAnnotatedFile());

        const updateFavoriteButtonIfNeeded = () => {
            const favoriteIconFill = document.getElementById(
                "pswp__icn-favorite-fill",
            );
            if (!favoriteIconFill) {
                return;
            }

            const button = favoriteButtonElement!;

            const af = currentAnnotatedFile();
            const showFavorite = af.annotation.showFavorite;
            showIf(button, showFavorite);

            if (!showFavorite) {
                return;
            }

            button.disabled = delegate.isFavoritePending(af);

            showIf(favoriteIconFill, !!delegate.isFavorite(af));
        };

        this.refreshCurrentSlideFavoriteButtonIfNeeded =
            updateFavoriteButtonIfNeeded;

        const updateLikeButtonIfNeeded = () => {
            const heartIconFill = document.getElementById(
                "pswp__icn-heart-fill",
            );
            const heartIconOutline = document.getElementById("pswp__icn-heart");
            if (!heartIconFill || !heartIconOutline) {
                return;
            }

            const af = currentAnnotatedFile();
            // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
            if (!af) return;
            const isLiked = delegate.isLiked(af);

            showIf(heartIconFill, isLiked);
            showIf(heartIconOutline, !isLiked);
        };

        this.refreshCurrentSlideLikeButtonIfNeeded = updateLikeButtonIfNeeded;

        const updateCommentCountIfNeeded = () => {
            const commentCountElement = document.querySelector<HTMLElement>(
                ".pswp__comment-count",
            );
            if (!commentCountElement) {
                return;
            }

            const af = currentAnnotatedFile();
            // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
            if (!af) return;
            const count = delegate.getCommentCount(af);
            commentCountElement.textContent = String(count);
        };

        this.refreshCurrentSlideCommentCountIfNeeded =
            updateCommentCountIfNeeded;

        const handleToggleFavorite = () => void toggleFavorite();

        const handleToggleFavoriteIfEnabled = () => {
            if (
                haveUser &&
                currentAnnotatedFile().annotation.showFavorite &&
                !delegate.isFavoritePending(currentAnnotatedFile())
            ) {
                handleToggleFavorite();
            }
        };

        const handleDownload = () => onDownload(currentAnnotatedFile());

        const handleDownloadIfEnabled = () => {
            if (currentFileAnnotation().showDownload) handleDownload();
        };

        const onVideoQualityChange = () => {
            if (shouldIgnoreNextVideoQualityChange) {
                shouldIgnoreNextVideoQualityChange = false;
                return;
            }

            toggleMediaChromeSettingsMenu();

            const fileID = currentAnnotatedFile().file.id;
            dataSource.forgetItemDataForFileID(fileID);
            if (originalVideoFileIDs.has(fileID)) {
                originalVideoFileIDs.delete(fileID);
            } else {
                originalVideoFileIDs.add(fileID);
            }

            pswp.refreshSlideContent(pswp.currIndex);
        };

        const showIf = (element: HTMLElement, condition: boolean) =>
            condition
                ? element.classList.remove("pswp__hidden")
                : element.classList.add("pswp__hidden");

        pswp.on("uiRegister", () => {
            const ui = pswp.ui!;

            ui.uiElementsData.find((e) => e.name == "zoom")!.order = 6;
            ui.uiElementsData.find((e) => e.name == "preloader")!.order = 10;

            if (isPublicAlbum && publicAlbumLogoHTML) {
                ui.registerElement({
                    name: "ente-logo",
                    order: 5,
                    isButton: true,
                    title: "Ente",
                    html: publicAlbumLogoHTML,
                    onClick: () => {
                        window.open("https://ente.com", "_blank", "noopener");
                    },
                });
            }

            ui.registerElement({
                name: "live",
                title: t("live"),
                order: 7,
                isButton: true,
                html: createPSRegisterElementIconHTML("live"),
                onInit: (buttonElement) => {
                    livePhotoPlayButtonElement = buttonElement;
                    pswp.on("change", () => {
                        const video = livePhotoVideoOnSlide(pswp.currSlide);
                        if (video) {
                            livePhotoUpdatePlayInitial(video);
                        } else {
                            showIf(buttonElement, false);
                        }
                    });
                },
                onClick: livePhotoTogglePlayIfPossible,
            });

            ui.registerElement({
                name: "vol",
                title: t("audio"),
                order: 8,
                isButton: true,
                html: createPSRegisterElementIconHTML("vol"),
                onInit: (buttonElement) => {
                    livePhotoMuteButtonElement = buttonElement;
                    pswp.on("change", () => {
                        const video = livePhotoVideoOnSlide(pswp.currSlide);
                        if (video) {
                            livePhotoUpdateMute(video);
                        } else {
                            showIf(buttonElement, false);
                        }
                    });
                },
                onClick: livePhotoToggleMuteIfPossible,
            });

            ui.registerElement({
                name: "error",
                order: 9,
                html: createPSRegisterElementIconHTML("error"),
                onInit: (errorElement, pswp) => {
                    pswp.on("change", () => {
                        const { fetchFailed, isContentLoading } =
                            currSlideData();
                        errorElement.classList.toggle(
                            "pswp__error--active",
                            !!fetchFailed && !isContentLoading,
                        );
                    });
                },
            });

            if (haveUser) {
                ui.registerElement({
                    name: "favorite",
                    title: t("favorite"),
                    order: 11,
                    isButton: true,
                    html: createPSRegisterElementIconHTML("favorite"),
                    onInit: (buttonElement) => {
                        favoriteButtonElement =
                            buttonElement as HTMLButtonElement;
                        pswp.on("change", updateFavoriteButtonIfNeeded);
                    },
                    onClick: handleToggleFavorite,
                });
            } else {
                ui.registerElement({
                    name: "download",
                    title: t("download"),
                    order: 11,
                    isButton: true,
                    html: createPSRegisterElementIconHTML("download"),
                    onInit: (buttonElement) =>
                        pswp.on("change", () =>
                            showIf(
                                buttonElement,
                                currentFileAnnotation().showDownload == "bar",
                            ),
                        ),
                    onClick: handleDownload,
                });
            }

            ui.registerElement({
                name: "info",
                title: t("info"),
                order: 13,
                isButton: true,
                html: createPSRegisterElementIconHTML("info"),
                onClick: handleViewInfo,
            });

            const shouldShowMoreButton = !showFullscreenButton || haveUser;

            if (shouldShowMoreButton) {
                ui.registerElement({
                    name: "more",
                    title: t("more"),
                    order: 16,
                    isButton: true,
                    html: createPSRegisterElementIconHTML("more"),
                    onInit: (buttonElement) => {
                        buttonElement.setAttribute("id", moreButtonID);
                        buttonElement.setAttribute("aria-haspopup", "true");
                    },
                    onClick: (_, buttonElement) => {
                        buttonElement.setAttribute("aria-controls", moreMenuID);
                        buttonElement.setAttribute("aria-expanded", "true");
                        onMore(buttonElement);
                    },
                });
            }

            if (showFullscreenButton) {
                ui.registerElement({
                    name: "fullscreen",
                    title: t("toggle_fullscreen"),
                    order: 18,
                    isButton: true,
                    html: createPSRegisterElementIconHTML("fullscreen"),
                    onInit: (buttonElement, pswp) => {
                        const updateIcon = () => {
                            const isFullscreen = !!document.fullscreenElement;
                            const fullscreenIcon = buttonElement.querySelector(
                                "#pswp__icn-fullscreen",
                            );
                            const exitIcon = buttonElement.querySelector(
                                "#pswp__icn-fullscreen-exit",
                            );
                            if (fullscreenIcon && exitIcon) {
                                showIf(
                                    fullscreenIcon as HTMLElement,
                                    !isFullscreen,
                                );
                                showIf(exitIcon as HTMLElement, isFullscreen);
                            }
                        };

                        document.addEventListener(
                            "fullscreenchange",
                            updateIcon,
                        );
                        pswp.on("destroy", () => {
                            document.removeEventListener(
                                "fullscreenchange",
                                updateIcon,
                            );
                        });

                        updateIcon();
                    },
                    onClick: handleToggleFullscreen,
                });
            }

            ui.registerElement({
                name: "media-controls",
                order: 30,
                appendTo: "root",
                html: hlsVideoControlsHTML(),
                onInit: (element, pswp) => {
                    mediaControlsContainerElement = element;
                    const menu = element.querySelector("#ente-quality-menu");
                    if (menu instanceof MediaChromeMenu) {
                        menu.addEventListener("change", onVideoQualityChange);
                    }
                    const fullscreenButton = element.querySelector(
                        "media-fullscreen-button",
                    );
                    fullscreenButton?.addEventListener(
                        "click",
                        handleFullscreenButtonClick,
                        { capture: true },
                    );
                    pswp.on("change", () =>
                        updateVideoControlsAndPlayback(currSlideData()),
                    );
                },
            });

            ui.registerElement({
                name: "bottom-right-controls",
                order: 31,
                appendTo: "root",
                html: bottomRightControlsHTML(),
                onInit: (element, pswp) => {
                    const captionEl =
                        element.querySelector<HTMLElement>(".pswp__caption")!;
                    const actionButtonsEl = element.querySelector<HTMLElement>(
                        ".pswp__action-buttons",
                    );

                    const updateSocialButtonsVisibility = () => {
                        if (!actionButtonsEl) return;
                        if (!_currentAnnotatedFile) return;
                        const af = currentAnnotatedFile();
                        const baseShow =
                            showSocialButtons ||
                            delegate.shouldShowSocialButtons(af);
                        const shouldShow = baseShow && enableComment;
                        actionButtonsEl.style.display = shouldShow
                            ? "flex"
                            : "none";
                    };

                    pswp.on("change", () => {
                        const { fileType, alt } = currSlideData();
                        const { text: captionText, wasTruncated } =
                            truncateCaptionIfNeeded(alt);
                        const captionP = captionEl.querySelector("p")!;
                        captionP.innerText = captionText ?? "";
                        if (wasTruncated) {
                            const moreLink = document.createElement("span");
                            moreLink.className = "pswp__caption-more";
                            moreLink.textContent = "More";
                            moreLink.addEventListener("click", handleViewInfo);
                            captionP.appendChild(moreLink);
                        }
                        captionEl.style.display = captionText
                            ? "block"
                            : "none";
                        captionEl.classList.toggle(
                            "ente-video",
                            fileType == FileType.video,
                        );
                        updateSocialButtonsVisibility();
                    });
                    const commentButton = element.querySelector<HTMLElement>(
                        '.pswp__action-button[aria-label="Comment"]',
                    );
                    commentButton?.addEventListener("click", onViewComments);
                    const likeButton = element.querySelector<HTMLElement>(
                        '.pswp__action-button[aria-label="Like"]',
                    );
                    likeButton?.addEventListener("click", onLikeClick);
                    likeButton?.addEventListener("contextmenu", (e) => {
                        e.preventDefault();
                        onViewLikes();
                    });
                    pswp.on("change", updateLikeButtonIfNeeded);
                    updateLikeButtonIfNeeded();
                    pswp.on("change", updateCommentCountIfNeeded);
                    updateCommentCountIfNeeded();
                    updateSocialButtonsVisibility();
                },
            });
        });

        const panner = (key: "w" | "a" | "s" | "d") => () => {
            const slide = pswp.currSlide!;
            const d = 80;
            switch (key) {
                case "w":
                    slide.pan.y += d;
                    break;
                case "a":
                    slide.pan.x += d;
                    break;
                case "s":
                    slide.pan.y -= d;
                    break;
                case "d":
                    slide.pan.x -= d;
                    break;
            }
            slide.panTo(slide.pan.x, slide.pan.y);
        };

        const handlePreviousSlide = () => pswp.prev();

        const handleNextSlide = () => pswp.next();

        // Arrow keys keep navigating briefly after landing on a video.
        const isUserLikelyNavigatingBetweenSlides = () =>
            Date.now() - lastSlideChangeEpochMilli < 700;

        const handleSeekBackOrPreviousSlide = () => {
            const video = videoVideoEl;
            if (
                video &&
                !isUserLikelyNavigatingBetweenSlides() &&
                video.currentTime > 0
            ) {
                video.currentTime = Math.max(video.currentTime - 5, 0);
            } else {
                handlePreviousSlide();
            }
        };

        const handleSeekForwardOrNextSlide = () => {
            const video = videoVideoEl;
            if (
                video &&
                !isUserLikelyNavigatingBetweenSlides() &&
                !video.ended
            ) {
                video.currentTime = video.currentTime + 5;
            } else {
                handleNextSlide();
            }
        };

        const handleTogglePlayIfPossible = () => {
            switch (currentAnnotatedFile().itemData.fileType) {
                case FileType.video:
                    videoTogglePlayIfPossible();
                    break;
                case FileType.livePhoto:
                    livePhotoTogglePlayIfPossible();
                    break;
            }
        };

        const handleToggleMuteIfPossible = () => {
            switch (currentAnnotatedFile().itemData.fileType) {
                case FileType.video:
                    videoToggleMuteIfPossible();
                    break;
                case FileType.livePhoto:
                    livePhotoToggleMuteIfPossible();
                    break;
            }
        };

        const handleToggleUIControls = () => {
            const areUIControlsVisible =
                pswp.element!.classList.toggle("pswp--ui-visible");
            if (!document.fullscreenElement) return;

            areFullscreenUIControlsHiddenByShortcut = !areUIControlsVisible;
            if (areUIControlsVisible) {
                scheduleFullscreenUIControlsAutoHide();
            } else {
                clearFullscreenUIControlsHideTimer();
            }
        };

        const isFocusVisibledOnUIControl = () => {
            const fv = document.querySelector(":focus-visible");
            if (fv && !fv.classList.contains("pswp")) {
                return true;
            }

            const f = document.querySelector(":focus");
            if (f?.tagName.startsWith("MEDIA-")) {
                return true;
            }

            return false;
        };

        const handleDelete = () => delegate.performKeyAction("delete");

        const handleToggleArchive = () =>
            delegate.performKeyAction("toggle-archive");

        const handleCopy = () => delegate.performKeyAction("copy");

        const handleToggleFullscreen = () =>
            delegate.performKeyAction("toggle-fullscreen");

        const handleHelp = () => delegate.performKeyAction("help");

        pswp.on("keydown", (pswpEvent) => {
            const e: KeyboardEvent = pswpEvent.originalEvent;

            if (delegate.shouldIgnoreKeyboardEvent(e)) {
                pswpEvent.preventDefault();
                return;
            }

            const key = e.key;
            const lkey = e.key.toLowerCase();

            if (isFocusVisibledOnUIControl() && key == "Escape") {
                const activeElement = document.activeElement;
                if (activeElement instanceof HTMLElement) activeElement.blur();
                pswpEvent.preventDefault();
                return;
            }

            let cb: (() => void) | undefined;
            if (e.shiftKey) {
                if (key == "?") cb = handleHelp;
            } else if (e.altKey) {
                switch (key) {
                    case "ArrowLeft":
                        cb = handlePreviousSlide;
                        break;
                    case "ArrowRight":
                        cb = handleNextSlide;
                        break;
                }
            } else if (e.metaKey || e.ctrlKey) {
                if (lkey == "c") cb = handleCopy;
            } else {
                switch (key) {
                    case " ":
                        if (!isFocusVisibledOnUIControl()) {
                            cb = handleTogglePlayIfPossible;
                        }
                        if (e.target == document.body) e.preventDefault();
                        break;
                    case "Backspace":
                    case "Delete":
                        cb = handleDelete;
                        break;
                    case "ArrowLeft":
                        cb = handleSeekBackOrPreviousSlide;
                        pswpEvent.preventDefault();
                        break;
                    case "ArrowRight":
                        cb = handleSeekForwardOrNextSlide;
                        pswpEvent.preventDefault();
                        break;
                    case "?":
                        cb = handleHelp;
                        break;
                }
                switch (lkey) {
                    case "w":
                    case "a":
                    case "s":
                    case "d":
                        cb = panner(lkey);
                        break;
                    case "h":
                        cb = handleToggleUIControls;
                        break;
                    case "m":
                        cb = handleToggleMuteIfPossible;
                        break;
                    case "l":
                        cb = handleToggleFavoriteIfEnabled;
                        break;
                    case "i":
                        cb = handleViewInfo;
                        break;
                    case "k":
                        cb = handleDownloadIfEnabled;
                        break;
                    case "x":
                        cb = handleToggleArchive;
                        break;
                    case "f":
                        cb = handleToggleFullscreen;
                        break;
                }
            }

            cb?.();
        });

        const blurMediaChromeFocus = (e: MouseEvent) => {
            const target = e.target;
            if (target instanceof HTMLElement) {
                switch (target.tagName) {
                    case "MEDIA-TIME-RANGE":
                    case "MEDIA-PLAY-BUTTON":
                    case "MEDIA-MUTE-BUTTON":
                    case "MEDIA-PIP-BUTTON":
                    case "MEDIA-FULLSCREEN-BUTTON":
                        setTimeout(() => target.blur(), 0);
                        break;
                }
            }
        };

        pswp.on("initialLayout", () => {
            pswp.element!.addEventListener("mousedown", blurMediaChromeFocus);
            document.addEventListener(
                "fullscreenchange",
                handleFullscreenChange,
            );
        });

        pswp.on("destroy", () => {
            pswp.element?.removeEventListener(
                "mousedown",
                blurMediaChromeFocus,
            );
            document.removeEventListener(
                "fullscreenchange",
                handleFullscreenChange,
            );
            document.removeEventListener(
                "mousemove",
                handleMouseMoveInFullscreen,
            );
            clearFullscreenUIControlsHideTimer();
            document.removeEventListener(
                "mousemove",
                handleFullscreenMouseMove,
            );
            if (hideVideoControlsTimer) {
                clearTimeout(hideVideoControlsTimer);
                hideVideoControlsTimer = undefined;
            }
            dataSource.fileViewerDidClose();
            onClose();
        });

        dataSource.fileViewerWillOpen();

        pswp.init();
    }

    closeIfNeeded() {
        // PhotoSwipe instances cannot be reused after destroy.
        this.pswp.close();
    }

    refreshCurrentSlideContent() {
        this.pswp.refreshSlideContent(this.pswp.currIndex);
    }

    refreshSlideOnFilesUpdateIfNeeded: () => void;
    refreshCurrentSlideFavoriteButtonIfNeeded: () => void;
    refreshCurrentSlideLikeButtonIfNeeded: () => void;
    refreshCurrentSlideCommentCountIfNeeded: () => void;
}

const hlsVideoHTML = (url: string, mediaControllerID: string) => `
<media-controller id="${mediaControllerID}" nohotkeys>
  <hls-video playsinline slot="media" src="${url}"></hls-video>
</media-controller>
`;

const videoHTML = (url: string, mediaControllerID: string) => `
<media-controller class="ente-vanilla-video" id="${mediaControllerID}" nohotkeys>
  <video playsinline slot="media" src="${url}"></video>
</media-controller>
`;

const hlsVideoControlsHTML = () => `
<div>
  <media-settings-menu id="ente-settings-menu" hidden anchor="ente-settings-menu-btn">
    <media-settings-menu-item>
      ${t("quality")}
      <media-chrome-menu id="ente-quality-menu" slot="submenu" hidden>
        <div slot="title">${t("quality")}</div>
        <media-chrome-menu-item type="radio">${t("auto")}</media-chrome-menu-item>
        <media-chrome-menu-item type="radio">${t("original")}</media-chrome-menu-item>
      </media-chrome-menu>
    </media-settings-menu-item>
    <media-settings-menu-item>
      ${t("speed")}
      <media-playback-rate-menu slot="submenu" hidden>
        <div slot="title">${t("speed")}</div>
      </media-playback-rate-menu>
    </media-settings-menu-item>
  </media-settings-menu>
  <media-control-bar>
    <media-loading-indicator noautohide></media-loading-indicator>
  </media-control-bar>
  <media-control-bar>
    <media-time-range></media-time-range>
  </media-control-bar>
  <media-control-bar>
    <media-play-button notooltip></media-play-button>
    <media-mute-button notooltip></media-mute-button>
    <media-time-display showduration notoggle></media-time-display>
    <media-text-display></media-text-display>
    <media-settings-menu-button id="ente-settings-menu-btn" invoketarget="ente-settings-menu" notooltip>
      <svg slot="icon" viewBox="0 0 24 24">${settingsSVGPath}</svg>
    </media-settings-menu-button>
    <media-pip-button notooltip></media-pip-button>
    <media-fullscreen-button notooltip></media-fullscreen-button>
  </media-control-bar>
</div>
`;

const livePhotoVideoHTML = (videoURL: string) => `
<video muted playsinline oncontextmenu="return false;">
  <source src="${videoURL}" />
</video>
`;

const bottomRightControlsHTML = () => `
<div class="pswp__caption"><p></p></div>
<div class="pswp__action-buttons">
  <button class="pswp__action-button" aria-label="Like">
    <svg viewBox="0 0 30 26" fill="none">${heartSVGPath} id="pswp__icn-heart" />${heartFillSVGPath} id="pswp__icn-heart-fill" /></svg>
  </button>
  <button class="pswp__action-button pswp__action-button--comment" aria-label="Comment">
    <svg viewBox="0 0 28 28" fill="none">${commentSVGPath} /></svg>
    <span class="pswp__comment-count"></span>
  </button>
</div>
`;

const truncateCaptionIfNeeded = (
    text: string | undefined,
): { text: string | undefined; wasTruncated: boolean } => {
    if (!text) return { text, wasTruncated: false };
    const maxLength = 154;
    if (text.length <= maxLength) return { text, wasTruncated: false };
    return { text: text.slice(0, maxLength) + "… ", wasTruncated: true };
};

const createElementFromHTMLString = (htmlString: string) => {
    const template = document.createElement("template");
    // Whitespace would become firstChild instead of the requested element.
    template.innerHTML = htmlString.trim();
    return template.content.firstChild!;
};

export const resetMoreMenuButtonOnMenuClose = (buttonElement: HTMLElement) => {
    buttonElement.removeAttribute("aria-controls");
    buttonElement.removeAttribute("aria-expanded");
};
