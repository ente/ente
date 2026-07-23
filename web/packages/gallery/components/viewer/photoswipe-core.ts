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
    /**
     * Called to obtain the latest list of files.
     *
     * [Note: Changes to underlying files when file viewer is open]
     *
     * The list of files shown by the viewer might change while the viewer is
     * open. We do not actively refresh the viewer when this happens since that
     * would result in the user's zoom / pan state being lost.
     *
     * However, we always read the latest list via the delegate, so any
     * subsequent user initiated slide navigation (e.g. moving to the next
     * slide) will use the new list.
     */
    getFiles: () => EnteFile[];
    /**
     * Return `true` if the provided file has been marked as a favorite by the
     * user.
     *
     * The toggle favorite button will not be shown for the file if
     * this callback returns `undefined`. Otherwise the return value determines
     * the toggle state of the toggle favorite button for the file.
     */
    isFavorite: (annotatedFile: T) => boolean | undefined;
    /**
     * Return `true` if there is an inflight request to update the favorite
     * status of the file.
     */
    isFavoritePending: (annotatedFile: T) => boolean;
    /**
     * Called when the user activates the toggle favorite action on a file.
     *
     * The toggle favorite button will be disabled for the file until the
     * promise returned by this function returns fulfills.
     *
     * > Note: The caller is expected to handle any errors that occur, and
     * > should not reject for foreseeable failures, otherwise the button will
     * > remain in the disabled state (until the file viewer is closed).
     */
    toggleFavorite: (annotatedFile: T) => Promise<void>;
    /**
     * Return `true` if the provided file has a green_heart reaction from the
     * current user.
     */
    isLiked: (annotatedFile: T) => boolean;
    /**
     * Return the number of comments on the provided file.
     *
     * If the file is viewed from within a collection context, this should
     * return the count of comments in that collection. Otherwise (gallery
     * view), it should return the count from the collection with most comments.
     */
    getCommentCount: (annotatedFile: T) => number;
    /**
     * Return `true` if social buttons (like, comment) should be shown for the
     * given file.
     *
     * This is used for gallery view where the file might belong to a shared
     * collection even though we're not directly viewing that collection.
     */
    shouldShowSocialButtons: (annotatedFile: T) => boolean;
    /**
     * Called when there is a keydown event, and our PhotoSwipe instance wants
     * to know if it should ignore it or handle it.
     *
     * The delegate should return true when it wants the keyboard event ignored,
     * e.g. for most keys while a viewer dialog is being displayed.
     */
    shouldIgnoreKeyboardEvent: (event: KeyboardEvent) => boolean;
    /**
     * Called when the user triggers a potential action using a keyboard
     * shortcut.
     *
     * The caller does not check if the action is valid in the current context,
     * so the delegate must validate and only then perform the action if it is
     * appropriate.
     */
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
    /**
     * `true` if we're running in the context of a logged in user, and so
     * various actions that modify the file should be shown.
     *
     * This is the static variant of various per file annotations that control
     * various modifications. If this is not `true`, then various actions like
     * favorite, delete etc are never shown. If this is `true`, then their
     * visibility depends on the corresponding annotation.
     *
     * For example, the favorite action is shown only if both this and the
     * {@link showFavorite} file annotation are true.
     */
    haveUser: boolean;
    /**
     * `true` when viewing a public album.
     */
    isPublicAlbum?: boolean;
    /**
     * Optional logo markup to place in the PhotoSwipe top bar.
     */
    publicAlbumLogoHTML?: string;
    /**
     * `true` if the like and comment action buttons should be shown.
     *
     * These buttons are shown only when viewing files in a shared album
     * (incoming or outgoing).
     */
    showSocialButtons: boolean;
    /**
     * `true` if the comments and reactions controls should be enabled.
     */
    enableComment: boolean;
    /**
     * Dynamic callbacks.
     *
     * The extra level of indirection allows these to be updated without
     * recreating us.
     */
    delegate: FileViewerPhotoSwipeDelegate<T>;
    /**
     * Called when the file viewer is closed.
     */
    onClose: () => void;
    /**
     * Called whenever the slide is initially displayed or changes, to obtain
     * various derived data for the file that is about to be displayed.
     *
     * @param file The current {@link EnteFile}. This is the same value as the
     * corresponding value in the current index of {@link getFiles} returned by
     * the delegate.
     *
     * @param itemData This is the best currently available {@link ItemData}
     * corresponding to the current file.
     */
    onAnnotate: (file: EnteFile, itemData: ItemData) => T;
    /**
     * Called when the user activates the info action on a file.
     */
    onViewInfo: (annotatedFile: T) => void;
    /**
     * Called when the user activates the comments action on a file.
     */
    onViewComments: () => void;
    /**
     * Called when the user activates the likes action on a file (right-click on heart).
     */
    onViewLikes: () => void;
    /**
     * Called when the user clicks the like button (left-click on heart).
     */
    onLikeClick: () => void;
    /**
     * Called when the user activates the download action on a file.
     */
    onDownload: (annotatedFile: T) => void;
    /**
     * Called when the user activates the more action.
     *
     * @param buttonElement The more button DOM element.
     */
    onMore: (buttonElement: HTMLElement) => void;
}

/**
 * The ID that is used by the "more" action button (if one is being displayed).
 *
 * @see also {@link moreMenuID}.
 */
export const moreButtonID = "ente-pswp-more-button";

/**
 * The ID this is expected to be used by the more menu that is shown in response
 * to the more action button being activated.
 *
 * @see also {@link moreButtonID}.
 */
export const moreMenuID = "ente-pswp-more-menu";

/**
 * This is the timeout after which the controls are hidden
 * by triggering the function for the H shortcut.
 */
const fullscreenControlsAutoHideDelayMS = 3000;

/**
 * A wrapper over {@link PhotoSwipe} to tailor its interface for use by our file
 * viewer.
 *
 * This is somewhat akin to the {@link PhotoSwipeLightbox}, except this doesn't
 * have any UI of its own, it only modifies PhotoSwipe Core's behaviour.
 *
 * [Note: PhotoSwipe]
 *
 * PhotoSwipe is a library that behaves similarly to the OG "lightbox" image
 * gallery JavaScript component from the middle ages.
 *
 * We don't need the lightbox functionality since we already have our own
 * thumbnail list (the "gallery"), so we only use the "Core" PhotoSwipe module
 * as our image viewer component.
 *
 * When the user clicks on one of the thumbnails in our gallery, we make the
 * root PhotoSwipe component visible. Within the DOM this is a dialog-like div
 * that takes up the entire viewport, shows the image, various controls etc.
 *
 * Documentation: https://photoswipe.com/.
 */
export class FileViewerPhotoSwipe<
    T extends FileViewerPhotoSwipeAnnotatedFile =
        FileViewerPhotoSwipeAnnotatedFile,
> {
    /**
     * The PhotoSwipe instance which we wrap.
     */
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
            // Opaque background.
            bgOpacity: 1,
            // The default, "zoom", cannot be used since we're not animating
            // from a thumbnail, so effectively "fade" is in effect anyway. Set
            // it still, just for and explicitness and documentation.
            showHideAnimationType: "fade",
            // The default imageClickAction is "zoom-or-close". When the image
            // is small and cannot be zoomed into further (which is common when
            // just the thumbnail has been loaded), this causes PhotoSwipe to
            // close. Disable this behaviour.
            clickToCloseNonZoomable: false,
            // The default `bgClickAction` is "close", but it is not always
            // apparent where the background is and where the controls are,
            // since everything is black, and so accidentally closing PhotoSwipe
            // is easy.
            //
            // Disable this behaviour, instead repurposing this action to behave
            // the same as the `tapAction` ("tap on PhotoSwipe viewport
            // content") and toggle the visibility of UI controls (We also have
            // auto hide based on mouse activity, but that would not have any
            // effect on touch devices)
            bgClickAction: "toggle-controls",
            // In single-file public viewer mode we keep Escape for nested UI
            // interactions while preventing accidental viewer closure.
            escKey: !disableEscapeClose,
            // Dedicated single-file viewer mode is page-like; gesture-driven
            // dismissals should not tear down the underlying viewer.
            pinchToClose: !disableGestureClose,
            closeOnVerticalDrag: !disableGestureClose,
            // At least on macOS, manual zooming with the trackpad is very
            // cumbersome (possibly because of the small multiplier in the
            // PhotoSwipe source, but I'm not sure). The other option to do a
            // manual zoom is to scroll (e.g. with the trackpad) but with the
            // CTRL key pressed, however on macOS this invokes the system zoom
            // if enabled in accessibility settings.
            //
            // Taking a step back though, the PhotoSwipe viewport is fixed, so
            // we can just directly map wheel / trackpad scrolls to zooming.
            wheelToZoom: true,
            // Chrome yells about incorrectly mixing focus and aria-hidden if we
            // leave this at the default (true) and then swipe between slides
            // fast, or show MUI drawers etc.
            //
            // See: [Note: Workarounds for unactionable ARIA warnings], but time
            // with a different library.
            trapFocus: false,
            // Set the index within files that we should open to. Subsequent
            // updates to the index will be tracked by PhotoSwipe internally.
            index: initialIndex,
            // Use "pswp-ente" as the main class name. Note that this is not
            // necessary, we could've target the "pswp" class too in our CSS
            // since we only have a single PhotoSwipe instance.
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

        // Various helper routines to obtain the file at `currIndex`.

        /**
         * Derived data about the currently displayed file.
         *
         * This is recomputed on-demand (by using the {@link onAnnotate}
         * callback) each time the slide changes, and cached until the next
         * slide change.
         *
         * Instead of accessing this property directly, code should funnel
         * through the `currentAnnotatedFile` helper function.
         */
        let _currentAnnotatedFile: T | undefined;

        /**
         * Non-null assert and casted the given {@link SlideData} as
         * {@link ItemData}.
         *
         * PhotoSwipe types specify currSlide.data to be of type `SlideData`,
         * but in our case these are {@link ItemData} instances which the type
         * doesn't reflect. So this is a method to consolidate the cast and
         * non-null assertion (the PhotoSwipe dialog shouldn't be visible if
         * there are no slides left).
         */
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
                // Guard: slide data can be unavailable during state transitions.
                // If unavailable, we keep using the cached annotatedFile.
                const slideData = pswp.currSlide?.data as ItemData | undefined;
                if (slideData) {
                    annotatedFile = onAnnotate(file, slideData);
                    _currentAnnotatedFile = annotatedFile;
                }
            }
            // By design, this should never be undefined after the initial slide
            // is shown. Use non-null assertion to maintain API contract.
            return annotatedFile!;
        };

        const currentFileAnnotation = () => currentAnnotatedFile().annotation;

        /**
         * [Note: Updates to the files prop for FileViewer]
         *
         * This function is called when the list of underlying files changes.
         *
         * These updates can be possibly spurious, since the list changes on
         * identity and not deep equality. Or they might be real but affect a
         * file that is not currently being shown.
         *
         * Apart from those cases, there are real updates that effect us:
         *
         * - If the file that was previously being shown is no longer being
         *   shown (e.g. it was deleted, or if the marked it archived in a
         *   context like "All" where archived files are not being shown), move
         *   to the next slide if possible, or close the viewer otherwise (e.g.
         *   user deleted the last one).
         *
         * - If the file that was previously being shown has moved to a new
         *   index (e.g. user changed the date in the file info panel), go to
         *   that new index.
         *
         * - If the file is still the same but the underlying file's updation
         *   time has changed (e.g. the user changed the name of the file in the
         *   file info panel), refresh the annotated file data cached by the
         *   viewer.
         *
         * When handling these cases, the intent is to minimize the need to call
         * `refreshSlideContent` as much as possible since that would cause the
         * zoom and pan state to be reset too.
         */
        this.refreshSlideOnFilesUpdateIfNeeded = () => {
            const prevFileID = _currentAnnotatedFile?.file.id;
            if (!prevFileID) return;

            const files = delegate.getFiles();
            const newFileCount = files.length;

            const newFile = files[pswp.currIndex];
            if (newFile?.id != prevFileID) {
                // File is either no longer there, or has moved.
                //
                // In either case, after repositioning ourselves to the new
                // index we also need to refresh the next (or both) neighbours.
                //
                // E.g. assume item at index 3 was removed. After refreshing,
                // the contents of the item previously at index 4, and now at
                // index 3, would be displayed. But the preloaded slide next to
                // us (showing item at index 4) would already be displaying the
                // same item, so that also needs to be refreshed to displaying
                // the item previously at index 5 (now at index 4).

                const newIndex = files.findIndex(({ id }) => id == prevFileID);

                if (newIndex == -1) {
                    // File is no longer present.
                    const i = pswp.currIndex;

                    if (i >= newFileCount) {
                        // If the last slide was removed, take one step back
                        // first (the code that calls us ensures that we don't
                        // get called if there are no more slides left).
                        this.pswp.prev();
                    }

                    // Refresh the slide at current index (the erstwhile
                    // neighbour), and refresh its subsequent neighbour (to get
                    // the new neighbour).
                    pswp.refreshSlideContent(i);
                    pswp.refreshSlideContent(i + 1 == newFileCount ? 0 : i + 1);
                } else {
                    // File has moved. Go to new index, and also refresh both
                    // its neighbours.
                    const i = newIndex;

                    pswp.goTo(i);
                    pswp.refreshSlideContent(i == 0 ? newFileCount - 1 : i - 1);
                    pswp.refreshSlideContent(i + 1 == newFileCount ? 0 : i + 1);
                }
            } else {
                // Calling `currentAnnotatedFile` has the side effect of
                // refreshing the cached annotated file if the `updationTime`
                // has changed.
                currentAnnotatedFile();
            }
        };

        /**
         * File (ID)s for which we should render the original, non-streamable,
         * video even if a HLS playlist is available.
         */
        const originalVideoFileIDs = new Set<number>();

        const intendedVideoQualityForFileID = (fileID: number) =>
            originalVideoFileIDs.has(fileID) ? "original" : "auto";

        // Provide data about slides to PhotoSwipe via callbacks
        // https://photoswipe.com/data-sources/#dynamically-generated-data

        pswp.addFilter("numItems", () => delegate.getFiles().length);

        pswp.addFilter("itemData", (_, index) => {
            const files = delegate.getFiles();
            const file = files[index]!;

            const videoQuality = intendedVideoQualityForFileID(file.id);

            const itemData = dataSource.itemDataForFile(
                file,
                { videoQuality },
                () => {
                    // When we get updated item data,
                    // 1. Clear cached data.
                    _currentAnnotatedFile = undefined;
                    // 2. Request a refresh.
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

        /**
         * File IDs for which we've already done initial live photo playback
         * attempts in the current session (invocation of file viewer).
         *
         * This not only allows us to skip triggering initial playback when
         * coming back to the same slide again (a behavioural choice), it also
         * allows us to skip retriggering playback when decoding of the image
         * component completes (a functional need).
         */
        const livePhotoInitialVisitedFileIDs = new Set<number>();

        /**
         * Last state of the live photo playback on initial display.
         */
        let livePhotoPlayInitial = true;

        /**
         * Set to the event listener that will be called at the end of the
         * initial playback of a live photo on the currently displayed slide.
         *
         * This will be present only during the initial playback (it will be
         * cleared when initial playback completes), and can also thus be used
         * as a pseudo `isPlayingLivePhotoInitial`.
         */
        let livePhotoPlayInitialEndedEvent:
            | { listener: () => void; video: HTMLVideoElement }
            | undefined;

        /**
         * Last state of the live photo muted toggle.
         */
        let livePhotoMute = true;

        /**
         * The live photo playback toggle DOM button element.
         */
        let livePhotoPlayButtonElement: HTMLElement | undefined;

        /**
         * The live photo muted toggle DOM button element.
         */
        let livePhotoMuteButtonElement: HTMLElement | undefined;

        /**
         * Update the state of the given {@link videoElement} and the
         * {@link livePhotoPlayButtonElement} to reflect
         * {@link livePhotoPlayInitial}.
         *
         * [Note: Live photo playback]
         *
         * 1. When opening a live photo, play it once unless
         *    {@link livePhotoPlayInitial} is disabled. This is the behaviour
         *    controlled by the {@link livePhotoUpdatePlayInitial} function.
         *
         * 2. If the user toggles playback of during the initial video playback,
         *    then remember their choice for the current session (invocation of
         *    file viewer) by disabling {@link livePhotoPlayInitial}.
         *
         * 3. Also keep track of which files have already been initial played in
         *    the current session (using {@link livePhotoInitialVisitedFileIDs}).
         *
         * 3. Post initial playback, user can play the video again in a loop by
         *    activating the {@link livePhotoPlayButtonElement}, which triggers
         *    the {@link livePhotoUpdatePlayToggle} function (and also resets
         *    {@link livePhotoPlayInitial}).
         */
        const livePhotoUpdatePlayInitial = (video: HTMLVideoElement) => {
            livePhotoUpdateUIState(video);

            // Ignore if we've already visited this file.
            const currFileID = currSlideData().fileID;
            if (livePhotoInitialVisitedFileIDs.has(currFileID)) {
                return;
            }

            // Otherwise mark it as visited.
            livePhotoInitialVisitedFileIDs.add(currFileID);

            // Remove any loop attributes we might've inherited from a
            // previously displayed live photos elements on the current slide.
            video.removeAttribute("loop");

            // Clear any other initial playback listeners.
            if (livePhotoPlayInitialEndedEvent) {
                const { video, listener } = livePhotoPlayInitialEndedEvent;
                video.removeEventListener("ended", listener);
                livePhotoPlayInitialEndedEvent = undefined;
            }

            if (livePhotoPlayInitial) {
                // Initial playback is enabled - Play the video once.
                //
                // There are a few playback cases (initial, resumed, adjacent
                // slide with a reused video element, new slide with a new video
                // element). Always start at the beginning in all cases for user
                // the feel the app is responding consistently.
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

        /**
         * See: [Note: Live photo playback]
         *
         * This function handles the playback toggled via an explicit user
         * action (button activation or keyboard shortcut).
         */
        const livePhotoUpdatePlayToggle = (video: HTMLVideoElement) => {
            if (video.paused || video.ended) {
                // Add the loop attribute.
                video.setAttribute("loop", "");

                // Take an explicit playback trigger as a signal to reset the
                // initial playback flag.
                //
                // This is the only way for the user to reset the initial
                // playback state (short of repopening the file viewer).
                livePhotoPlayInitial = true;

                video.currentTime = 0;
                void abortablePlayVideo(video);
            } else {
                // Remove the loop attribute (not necessarily needed because we
                // remove it on slide change too, but good to clean up after
                // ourselves).
                video.removeAttribute("loop");

                // If we're in the middle of the initial playback, remember the
                // user's choice to disable autoplay.
                if (livePhotoPlayInitialEndedEvent) {
                    livePhotoPlayInitial = false;

                    // And reset the event handler.
                    const { video, listener } = livePhotoPlayInitialEndedEvent;
                    video.removeEventListener("ended", listener);
                    livePhotoPlayInitialEndedEvent = undefined;
                }

                video.pause();
            }

            livePhotoUpdateUIState(video);
        };

        /**
         * A wrapper over video.play that prevents Chrome from spamming the
         * console with errors about interrupted plays when scrolling through
         * files fast by keeping arrow keys pressed, or when the slide is reloaded.
         */
        const abortablePlayVideo = async (videoElement: HTMLVideoElement) => {
            try {
                await videoElement.play();
            } catch (e) {
                // Known message strings prefixes.
                // - "The play() request was interrupted by a call to pause()."
                // - "The play() request was interrupted because the media was removed from the document."

                if (
                    e instanceof Error &&
                    e.name == "AbortError" &&
                    e.message.startsWith("The play() request was interrupted")
                ) {
                    // Ignore.
                } else {
                    throw e;
                }
            }
        };

        /**
         * Update the state of the given {@link videoElement} and the
         * {@link livePhotoMuteButtonElement} to reflect {@link livePhotoMute}.
         */
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

        /**
         * Toggle the playback, if possible, of a live photo that's being shown
         * on the current slide.
         */
        const livePhotoTogglePlayIfPossible = () => {
            const buttonElement = livePhotoPlayButtonElement;
            const video = livePhotoVideoOnSlide(pswp.currSlide);
            if (!buttonElement || !video) return;

            livePhotoUpdatePlayToggle(video);
        };

        /**
         * Toggle the muted status, if possible, of a live photo that's being shown
         * on the current slide.
         */
        const livePhotoToggleMuteIfPossible = () => {
            const buttonElement = livePhotoMuteButtonElement;
            const video = livePhotoVideoOnSlide(pswp.currSlide);
            if (!buttonElement || !video) return;

            livePhotoMute = !livePhotoMute;
            livePhotoUpdateMute(video);
        };

        /**
         * The DOM element housing the media-control-bar and friends.
         */
        let mediaControlsContainerElement: HTMLElement | undefined;

        /**
         * True if the next change to the videoQuality is initiated by us. This
         * is used by the "change" event listener to ignore these events,
         * avoiding a cyclic update loop.
         */
        let shouldIgnoreNextVideoQualityChange = false;

        /**
         * Update the media controls for the given {@link itemData}.
         *
         * - Show controls only for videos.
         * - Keep controls visible but disabled while video playback is loading.
         * - Link controls to the media controller once available.
         */
        const updateVideoControlsAndPlayback = (itemData: ItemData) => {
            // For reasons possibly related to the 1 tick wait in the hls-video
            // implementation (`await Promise.resolve()`), the association
            // between media-controller and media-control-bar doesn't get
            // established on the first slide if we reopen the file viewer.
            //
            // See also: https://github.com/muxinc/media-chrome/issues/940
            //
            // As a workaround, defer the association to the next tick.
            setTimeout(() => _updateVideoControlsAndPlayback(itemData), 0);
        };

        /**
         * Handle click on the media-fullscreen-button by intercepting it and
         * using document-level fullscreen instead.
         *
         * The default behavior of media-fullscreen-button puts only the
         * media-controller element into fullscreen, which hides the PhotoSwipe
         * UI controls (close, info, navigation, etc.). By using document-level
         * fullscreen on document.body, all controls remain accessible.
         *
         * In fullscreen mode, we hide the top navigation bar and only show the
         * video timeline controls at the bottom (with auto-hide behavior).
         */
        const handleFullscreenButtonClick = (e: Event) => {
            e.stopPropagation();
            e.preventDefault();
            if (document.fullscreenElement) {
                void document.exitFullscreen();
            } else {
                void document.body.requestFullscreen();
                // Hide top navigation bar in fullscreen, show only video controls
                pswp.element?.classList.add("pswp--video-fullscreen");
                // Track mouse movement to show controls when near bottom
                document.addEventListener(
                    "mousemove",
                    handleMouseMoveInFullscreen,
                );
            }
        };

        // Timer variable for hiding the controls
        let fullscreenUIControlsHideTimer:
            | ReturnType<typeof setTimeout>
            | undefined;

        /**
         * This variable is used to check whether the controls were
         * intentionally hidden by the H keypress, if so then
         * moving the mouse no longer bring the conrol back.
         */
        let areFullscreenUIControlsHiddenByShortcut = false;

        // Function to clear the timeout.
        const clearFullscreenUIControlsHideTimer = () => {
            if (fullscreenUIControlsHideTimer) {
                clearTimeout(fullscreenUIControlsHideTimer);
                fullscreenUIControlsHideTimer = undefined;
            }
        };

        /**
         * Function start the 3 second timer that hides the main Photoswipe UI
         * controls in the fullscreen.
         */
        const scheduleFullscreenUIControlsAutoHide = () => {
            clearFullscreenUIControlsHideTimer();
            fullscreenUIControlsHideTimer = setTimeout(() => {
                pswp.element?.classList.remove("pswp--ui-visible");
                fullscreenUIControlsHideTimer = undefined;
            }, fullscreenControlsAutoHideDelayMS);
        };

        /**
         * If the photoswipe controls were actually auto hidden
         * and not by the H shortcut then, this function brings
         * them back on mouse movement.
         */
        const handleFullscreenMouseMove = () => {
            if (!document.fullscreenElement) return;
            if (areFullscreenUIControlsHiddenByShortcut) return;

            pswp.element?.classList.add("pswp--ui-visible");
            scheduleFullscreenUIControlsAutoHide();
        };

        /**
         * Update UI state when fullscreen mode changes (e.g., user presses Esc).
         */
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

            // Exiting fullscreen - restore the top navigation bar
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

        /**
         * Timer ID for hiding video controls after mouse inactivity in
         * fullscreen.
         */
        let hideVideoControlsTimer: ReturnType<typeof setTimeout> | undefined;

        /**
         * Show video controls on mouse movement, hide after inactivity.
         */
        const handleMouseMoveInFullscreen = () => {
            pswp.element?.classList.add("pswp--controls-visible");

            // Clear any pending hide timer
            if (hideVideoControlsTimer) {
                clearTimeout(hideVideoControlsTimer);
            }

            // Hide controls after inactivity
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

                // Hide the auto option, keeping track of if we did indeed
                // change something.
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
                // Check first to avoid spurious updates.
                if (qualityMenu.value != value) {
                    // Set a flag to avoid infinite update loop.
                    shouldIgnoreNextVideoQualityChange = true;
                    // Setting the value will close it.
                    qualityMenu.value = value;
                } else {
                    // Close it ourselves otherwise if we changed the menu.
                    if (didChangeHide) {
                        closeMediaChromeSettingsMenuIfOpen();
                    }
                }
            }

            // Autoplay (unless the video has ended).
            const video = videoVideoEl;
            if (video?.paused && !video.ended) void video.play();
        };

        /**
         * Toggle the settings menu by activating the menu button.
         *
         * This should be more robust than us trying to reverse engineer the
         * internal media chrome logic to open and close the menu. However, the
         * caveat is that this will only work for closing the menu (our goal)
         * if the menu is already open.
         */
        const toggleMediaChromeSettingsMenu = () => {
            const menuButton = document.querySelector(
                "media-settings-menu-button",
            );
            if (menuButton instanceof MediaChromeMenuButton) {
                menuButton.handleClick();

                // See: [Note: Media chrome focus workaround]
                //
                // Whatever media chrome is doing internally, it requires us to
                // drop the focus multiple times (Removing either of these calls
                // is not enough).
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
            // PhotoSwipe emits stale contentAppend events. e.g. when changing
            // the video quality, we'll first get "contentAppend" (and "change")
            // with the latest item data, but then later PhotoSwipe will call
            // "contentAppend" again with stale data.
            //
            // To ignore these, we check the `hasSlide` attribute. I'm not sure
            // if this is a foolproof workaround.
            //
            // See also https://github.com/dimsemenov/PhotoSwipe/issues/2045.
            if (!e.content.hasSlide) {
                log.debug(() => ["Ignoring stale contentAppend", e]);
                return;
            }

            const { fileID, fileType, videoURL } = asItemData(e.content.data);

            // For the initial slide, "contentAppend" will get called after the
            // "change" event, so we need to wire up the controls, or hide them,
            // for the initial slide here also (in addition to in "change").
            if (currSlideData().fileID == fileID) {
                updateVideoControlsAndPlayback(currSlideData());
            }

            if (fileType != FileType.livePhoto || !videoURL) {
                // Not a live photo, or its video hasn't loaded yet.
                return;
            }

            // Rest of this function deals with live photos.

            // This slide is displaying a live photo. Append a video element to
            // show its video part.

            const img = e.content.element!;
            const video = createElementFromHTMLString(
                livePhotoVideoHTML(videoURL),
            ) as HTMLVideoElement;
            const container = e.content.slide!.container;
            container.style = "position: relative";
            container.appendChild(video);
            // Set z-index to 1 to keep it on top, and set pointer-events to
            // none to pass the clicks through.
            video.style =
                "position: absolute; top: 0; left: 0; z-index: 1; pointer-events: none;";

            // Size it to the underlying image.
            video.style.width = img.style.width;
            video.style.height = img.style.height;

            // "contentAppend" can get called both before, or after, "change",
            // and we need to handle both potential sequences for the initial
            // display of the video. Here we handle the case where "change" has
            // already been called, but now "contentAppend" is happening.

            if (currSlideData().fileID == fileID) {
                livePhotoUpdatePlayInitial(video);
                livePhotoUpdateMute(video);
            }
        });

        /**
         * Helper function to extract the video element from a slide that is
         * showing a live photo.
         */
        const livePhotoVideoOnSlide = (slide: typeof pswp.currSlide) =>
            asItemData(slide?.data).fileType == FileType.livePhoto
                ? slide?.container.getElementsByTagName("video")[0]
                : undefined;

        pswp.on("imageSizeChange", ({ content, width, height }) => {
            const video = livePhotoVideoOnSlide(content.slide);
            if (!video) {
                // We might have been called before "contentAppend".
                return;
            }

            // This slide is displaying a live photo. Resize the size of the
            // video element to match that of the image.

            video.style.width = `${width}px`;
            video.style.height = `${height}px`;
        });

        /**
         * Get the video element, if any, that is a descendant of the given HTML
         * element.
         *
         * While the return type is an {@link HTMLVideoElement}, the result can
         * also be an instance of a media-chrome `CustomVideoElement`,
         * specifically a {@link HlsVideoElement}.
         * https://github.com/muxinc/media-elements/blob/main/packages/hls-video-element/hls-video-element.js
         *
         * The media-chrome `CustomVideoElement`s provide the same API as the
         * browser's built-in {@link HTMLVideoElement}s, so we can use the same
         * methods on them.
         *
         * For ergonomic use at call sites, it accepts an optional.
         */
        const queryVideoElement = (element: HTMLElement | undefined) =>
            element?.querySelector<HTMLVideoElement>("video, hls-video");

        pswp.on("contentDeactivate", (e) => {
            // PhotoSwipe invokes this event when moving away from a slide.
            //
            // However it might not have an effect until we move out of preload
            // range. See: [Note: File viewer preloading and contentDeactivate].

            const fileID = asItemData(e.content.data).fileID;
            if (fileID) dataSource.forgetItemDataForFileIDIfNeeded(fileID);

            // Pause the video element, if any, when we move away from the
            // slide.
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

        /**
         * If the current slide is showing a video, then the DOM video element
         * showing that video.
         *
         * See also {@link queryVideoElement}.
         */
        let videoVideoEl: HTMLVideoElement | undefined;

        /**
         * The epoch time (milliseconds) when the latest slide change happened.
         */
        let lastSlideChangeEpochMilli = Date.now();

        pswp.on("change", () => {
            const itemData = currSlideData();

            // For each slide ("item holder"), mirror the "aria-hidden" state
            // into the "inert" property so that keyboard navigation via tabs
            // does not cycle through to the hidden slides (e.g. if the hidden
            // slide is a video element with browser provided controls).

            pswp.mainScroll.itemHolders.forEach(({ el }) => {
                if (el.getAttribute("aria-hidden") == "true") {
                    el.setAttribute("inert", "");
                } else {
                    el.removeAttribute("inert");
                }
            });

            if (itemData.fileType == FileType.video) {
                // We use content.element instead of container here because
                // pswp.currSlide.container.getElementsByTagName("video") does
                // not work for the first slide when we reach here during the
                // initial "change".
                //
                // It works subsequently, which is why, e.g., we can use it to
                // pause the video in "contentDeactivate".
                const contentElement = pswp.currSlide?.content.element;
                videoVideoEl = queryVideoElement(contentElement) ?? undefined;
            } else {
                videoVideoEl = undefined;
            }

            lastSlideChangeEpochMilli = Date.now();
        });

        /**
         * Toggle the playback, if possible, of the video that's being shown on
         * the current slide.
         */
        const videoTogglePlayIfPossible = () => {
            const video = videoVideoEl;
            if (!video) return;

            if (video.paused || video.ended) {
                void video.play();
            } else {
                video.pause();
            }
        };

        /**
         * Toggle the muted status, if possible, of the video that's being shown on
         * the current slide.
         */
        const videoToggleMuteIfPossible = () => {
            // Go via the media chrome mute button when muting, because
            // otherwise the local storage that the media chrome internally
            // manages ('media-chrome-pref-muted' which can be 'true' or
            // 'false') gets out of sync with the playback state.
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
                // Early return if we're not currently being shown, to implement
                // the "IfNeeded" semantics.
                return;
            }

            const button = favoriteButtonElement!;

            const af = currentAnnotatedFile();
            const showFavorite = af.annotation.showFavorite;
            showIf(button, showFavorite);

            if (!showFavorite) {
                // Nothing more to do.
                return;
            }

            // Update the button interactivity based on pending requests.
            button.disabled = delegate.isFavoritePending(af);

            // Update the fill visibility based on the favorite status.
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
                // Early return if we're not currently being shown.
                return;
            }

            const af = currentAnnotatedFile();
            // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
            if (!af) return; // Guard against undefined during initialization
            const isLiked = delegate.isLiked(af);

            // Show fill (green) if liked, show outline (white) if not liked
            showIf(heartIconFill, isLiked);
            showIf(heartIconOutline, !isLiked);
        };

        this.refreshCurrentSlideLikeButtonIfNeeded = updateLikeButtonIfNeeded;

        const updateCommentCountIfNeeded = () => {
            const commentCountElement = document.querySelector<HTMLElement>(
                ".pswp__comment-count",
            );
            if (!commentCountElement) {
                // Early return if we're not currently being shown.
                return;
            }

            const af = currentAnnotatedFile();
            // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
            if (!af) return; // Guard against undefined during initialization
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
                // Ignore changes that we ourselves initiated on slide change.
                shouldIgnoreNextVideoQualityChange = false;
                return;
            }

            // The menu is open at this point, so toggling it is equivalent to
            // closing it.
            toggleMediaChromeSettingsMenu();

            // Currently there are only two entries in the video quality menu,
            // and the callback only gets invoked if the value gets changed from
            // the current value. So we can assume toggle semantics when
            // implementing the logic below.

            const fileID = currentAnnotatedFile().file.id;
            dataSource.forgetItemDataForFileID(fileID);
            if (originalVideoFileIDs.has(fileID)) {
                originalVideoFileIDs.delete(fileID);
            } else {
                originalVideoFileIDs.add(fileID);
            }

            // Refresh the slide so that the video is fetched afresh, but using
            // the updated `originalVideoFileIDs` value for it.
            pswp.refreshSlideContent(pswp.currIndex);
        };

        const showIf = (element: HTMLElement, condition: boolean) =>
            condition
                ? element.classList.remove("pswp__hidden")
                : element.classList.add("pswp__hidden");

        // Add our custom UI elements to inside the PhotoSwipe dialog.
        //
        // API docs for registerElement:
        // https://photoswipe.com/adding-ui-elements/#uiregisterelement-api
        //
        // The "order" prop is used to position items. Some landmarks:
        // - counter: 5
        // - zoom: 6 (default is 10)
        // - preloader: 10 (default is 7)
        // - close: 20
        pswp.on("uiRegister", () => {
            const ui = pswp.ui!;

            // Move the zoom button to the left so that it is in the same place
            // as the other items like preloader or the error indicator that
            // come and go as files get loaded. Also modify the default orders
            // so that there is more space for the error / live indicators.
            //
            // We cannot use the PhotoSwipe "uiElement" filter to modify the
            // order since that only allows us to edit the DOM element, not the
            // underlying UI element data.
            ui.uiElementsData.find((e) => e.name == "zoom")!.order = 6;
            ui.uiElementsData.find((e) => e.name == "preloader")!.order = 10;

            // Register our custom elements...

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
                            // Not a live photo, or its video hasn't loaded yet.
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
                            // Not a live photo, or its video hasn't loaded yet.
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

            // Only one of these two ("favorite" and "download") will end
            // up being shown, so they can safely share the same order.
            if (haveUser) {
                ui.registerElement({
                    name: "favorite",
                    title: t("favorite"),
                    order: 11,
                    isButton: true,
                    html: createPSRegisterElementIconHTML("favorite"),
                    onInit: (buttonElement) => {
                        favoriteButtonElement =
                            // The cast should be safe (unless there is a
                            // PhotoSwipe bug) since we set isButton to true.
                            buttonElement as HTMLButtonElement;
                        pswp.on("change", updateFavoriteButtonIfNeeded);
                    },
                    onClick: handleToggleFavorite,
                });
            } else {
                // When we don't have a user (i.e. in the context of public
                // albums), the download button is shown (if enabled for that
                // album) instead of the favorite button as the first action.
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

            // Only show the more button if there are meaningful items to display.
            // When fullscreen is shown in the toolbar (showFullscreenButton=true)
            // and we're in a context without user actions (no delete, archive, etc),
            // hide the more menu since it would only contain fullscreen and shortcuts.
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
                        // See also: `resetMoreMenuButtonOnMenuClose`.
                        buttonElement.setAttribute("aria-controls", moreMenuID);
                        buttonElement.setAttribute("aria-expanded", "true");
                        onMore(buttonElement);
                    },
                });
            }

            // Add fullscreen button as a primary action for embed app
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

                        // Update icon on fullscreen changes
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

                        // Initialize icon state
                        updateIcon();
                    },
                    onClick: handleToggleFullscreen,
                });
            }

            ui.registerElement({
                name: "media-controls",
                // Arbitrary order towards the end.
                order: 30,
                appendTo: "root",
                html: hlsVideoControlsHTML(),
                onInit: (element, pswp) => {
                    mediaControlsContainerElement = element;
                    const menu = element.querySelector("#ente-quality-menu");
                    if (menu instanceof MediaChromeMenu) {
                        menu.addEventListener("change", onVideoQualityChange);
                    }
                    // Override the media-fullscreen-button to use document-level
                    // fullscreen instead of element-level fullscreen. This
                    // ensures the PhotoSwipe UI controls remain accessible.
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
                // After the video controls so that we don't get occluded by
                // them (nb: the caption will hide when the video is playing).
                order: 31,
                appendTo: "root",
                html: bottomRightControlsHTML(),
                onInit: (element, pswp) => {
                    const captionEl =
                        element.querySelector<HTMLElement>(".pswp__caption")!;
                    // Get the action buttons container.
                    const actionButtonsEl = element.querySelector<HTMLElement>(
                        ".pswp__action-buttons",
                    );

                    const updateSocialButtonsVisibility = () => {
                        if (!actionButtonsEl) return;
                        // Guard: _currentAnnotatedFile can be undefined during
                        // initialization before the first slide is shown.
                        if (!_currentAnnotatedFile) return;
                        // Show buttons if: static showSocialButtons is true
                        // OR delegate says this file should show buttons
                        // (file in shared collection).
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
                        // Update social buttons visibility on each slide change.
                        updateSocialButtonsVisibility();
                    });
                    // Wire up click handler for the comment button.
                    const commentButton = element.querySelector<HTMLElement>(
                        '.pswp__action-button[aria-label="Comment"]',
                    );
                    commentButton?.addEventListener("click", onViewComments);
                    // Wire up click handlers for the like button.
                    const likeButton = element.querySelector<HTMLElement>(
                        '.pswp__action-button[aria-label="Like"]',
                    );
                    // Left-click: trigger like action (may open album selector)
                    likeButton?.addEventListener("click", onLikeClick);
                    // Right-click: open likes sidebar
                    likeButton?.addEventListener("contextmenu", (e) => {
                        e.preventDefault();
                        onViewLikes();
                    });
                    // Update like button state on slide change and initially.
                    pswp.on("change", updateLikeButtonIfNeeded);
                    updateLikeButtonIfNeeded();
                    // Update comment count on slide change and initially.
                    pswp.on("change", updateCommentCountIfNeeded);
                    updateCommentCountIfNeeded();
                    // Initial visibility check.
                    updateSocialButtonsVisibility();
                },
            });
        });

        // Pan action handlers

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

        // Actions we handle ourselves.

        const handlePreviousSlide = () => pswp.prev();

        const handleNextSlide = () => pswp.next();

        /**
         * The arrow keys are used both for navigating through slides, and for
         * scrubbing through the video.
         *
         * When on a video, the navigation requires the option prefix (since
         * scrubbing through the video is a more common requirement). However
         * this breaks the user's flow when they are navigating between slides
         * fast by using the arrow keys - they land on a video and the
         * navigation stops.
         *
         * So as a special case, we keep using arrow keys for navigation for the
         * first 700 milliseconds when the user lands on a slide.
         */
        const isUserLikelyNavigatingBetweenSlides = () =>
            Date.now() - lastSlideChangeEpochMilli < 700; /* ms */

        const handleSeekBackOrPreviousSlide = () => {
            const video = videoVideoEl;
            if (
                video &&
                !isUserLikelyNavigatingBetweenSlides() &&
                // If the video is at the beginning, then use the left arrow to
                // move to the preview slide.
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
                // If the video has ended, then use right arrow to move to the
                // next slide.
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

        // Toggle controls infrastructure

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

        // Return true if the current keyboard focus is on any of the UI
        // controls (e.g. as a result of user tabbing through them).
        const isFocusVisibledOnUIControl = () => {
            const fv = document.querySelector(":focus-visible");
            if (fv && !fv.classList.contains("pswp")) {
                return true;
            }

            // Media Chrome does its own thing and doesn't seem to gain the
            // :focus-visible pseudo class even though it visually looks that
            // way. We need to add a special case for it.
            const f = document.querySelector(":focus");
            if (f?.tagName.startsWith("MEDIA-")) {
                return true;
            }

            return false;
        };

        // Some actions routed via the delegate

        const handleDelete = () => delegate.performKeyAction("delete");

        const handleToggleArchive = () =>
            delegate.performKeyAction("toggle-archive");

        const handleCopy = () => delegate.performKeyAction("copy");

        const handleToggleFullscreen = () =>
            delegate.performKeyAction("toggle-fullscreen");

        const handleHelp = () => delegate.performKeyAction("help");

        pswp.on("keydown", (pswpEvent) => {
            const e: KeyboardEvent = pswpEvent.originalEvent;

            // Ignore keyboard events when one of our sub-dialogs are open.
            if (delegate.shouldIgnoreKeyboardEvent(e)) {
                pswpEvent.preventDefault();
                return;
            }

            const key = e.key;
            // Even though we ignore shift, Caps lock might still be on.
            const lkey = e.key.toLowerCase();

            // When one of the controls on the screen has a visible focus
            // indicator, we want the Escape key to blur its focus instead of
            // closing the PhotoSwipe dialog.
            if (isFocusVisibledOnUIControl() && key == "Escape") {
                const activeElement = document.activeElement;
                if (activeElement instanceof HTMLElement) activeElement.blur();
                pswpEvent.preventDefault();
                return;
            }

            // Keep the keybindings such that they don't use modifiers, because
            // these are more likely to interfere with browser shortcuts.
            //
            // For example, Cmd-D adds a bookmark, which is why we don't use it
            // for download.
            //
            // There are some exception, e.g. Ctrl/Cmd-C, which we intercept to
            // copy the image since that should match the user's expectation.

            let cb: (() => void) | undefined;
            if (e.shiftKey) {
                // Ignore except "?" for help.
                if (key == "?") cb = handleHelp;
            } else if (e.altKey) {
                // Ignore except if for arrow keys since when showing a video,
                // the arrow keys are used for seeking, and the normal arrow key
                // function (slide movement) needs the Alt/Opt modifier.
                switch (key) {
                    case "ArrowLeft":
                        cb = handlePreviousSlide;
                        break;
                    case "ArrowRight":
                        cb = handleNextSlide;
                        break;
                }
            } else if (e.metaKey || e.ctrlKey) {
                // Ignore except Ctrl/Cmd-C for copy
                if (lkey == "c") cb = handleCopy;
            } else {
                switch (key) {
                    case " ":
                        // Space activates controls when they're focused, so
                        // only act on it if no specific control is focused.
                        if (!isFocusVisibledOnUIControl()) {
                            cb = handleTogglePlayIfPossible;
                        }
                        // Prevent the browser's default space behaviour of
                        // scrolling the file list in the background (which is
                        // not appropriate when the file viewer is visible).
                        if (e.target == document.body) e.preventDefault();
                        break;
                    case "Backspace":
                    case "Delete":
                        cb = handleDelete;
                        break;
                    case "ArrowLeft":
                        cb = handleSeekBackOrPreviousSlide;
                        // Prevent PhotoSwipe's default handling of this key.
                        pswpEvent.preventDefault();
                        break;
                    case "ArrowRight":
                        cb = handleSeekForwardOrNextSlide;
                        // Prevent PhotoSwipe's default handling of this key.
                        pswpEvent.preventDefault();
                        break;
                    // We check for "?"" both with an without shift, since some
                    // keyboards might have it emittable without shift.
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

        /**
         * [Note: Media chrome focus workaround]
         *
         * The media-chrome-button elements (e.g, the play button, but also
         * others, including the menu) retain focus after clicking on them.
         * e.g., if I click the "media-mute-button" to activate it, then the
         * mute button grabs focus (but not :focus-visible). So it doesn't
         * appear focused visually, but then later if I press Space or Enter,
         * then the mute button activates again instead of toggling video
         * playback (as our keyboard shortcut is meant to do).
         *
         * I'm not sure who is at fault here, but this behaviour ends up being
         * irritating. e.g. say I change the quality in the menu, and press
         * space to play - well, the space no longer works because the media
         * chrome has grabbed focus and instead activates itself, reopening the
         * settings menu.
         *
         * As a workaround, we ask media chrome to drop focus on mouse clicks.
         * This should not impact keyboard activations.
         *
         * This workaround is likely to cause problems in the future, but I
         * can't find a better way short of upstream media chrome changes.
         */
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

        // The PhotoSwipe dialog has being closed and the animations have
        // completed.
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
            // Let our parent know that we have been closed.
            onClose();
        });

        // Let our data source know that we're about to open.
        dataSource.fileViewerWillOpen();

        // Initializing PhotoSwipe adds it to the DOM as a dialog-like div with
        // the class "pswp".
        pswp.init();
    }

    /**
     * Close this instance of {@link FileViewerPhotoSwipe} if it hasn't itself
     * initiated the close.
     *
     * This instance **cannot** be used after this function has been called.
     */
    closeIfNeeded() {
        // Closing PhotoSwipe removes it from the DOM.
        //
        // This will only have an effect if we're being closed externally (e.g.
        // if the user selects an album in the file info).
        //
        // If this cleanup function is running in the sequence where we were
        // closed internally (e.g. the user activated the close button within
        // the file viewer), then PhotoSwipe will ignore this extra close.
        this.pswp.close();
    }

    /**
     * Reload the current slide, asking the data source for its data afresh.
     */
    refreshCurrentSlideContent() {
        this.pswp.refreshSlideContent(this.pswp.currIndex);
    }

    /**
     * Ask the delegate for the files information afresh, and perform the
     * sequence described in [Note: Updates to the files prop for FileViewer].
     */
    refreshSlideOnFilesUpdateIfNeeded: () => void;

    /**
     * Refresh the favorite button (if indeed it is visible at all) on the
     * current slide, asking the delegate for the latest state.
     *
     * We do this piecemeal update instead of a full refresh because a full
     * refresh would cause, e.g., the pan and zoom to be reset.
     */
    refreshCurrentSlideFavoriteButtonIfNeeded: () => void;

    /**
     * Refresh the like button (heart) on the current slide, asking the
     * delegate for the latest like state.
     */
    refreshCurrentSlideLikeButtonIfNeeded: () => void;

    /**
     * Refresh the comment count on the current slide, asking the delegate
     * for the latest comment count.
     */
    refreshCurrentSlideCommentCountIfNeeded: () => void;
}

// Requires the following imports to register the Web components we use:
//
//     import "hls-video-element";
//     import "media-chrome";
//     import "media-chrome/menu";
//
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

/**
 * HTML for controls associated with {@link hlsVideoHTML} or {@link videoHTML}.
 *
 * To make these functional, the `media-control-bar` requires the
 * `mediacontroller="${mediaControllerID}"` attribute.
 *
 * Notes:
 *
 * - Examples: https://media-chrome.mux.dev/examples/vanilla/
 *
 * - When PiP is active and the video moves out, the browser displays some
 *   indicator (browser specific) in the in-page video element. This element and
 *   text is not under our control.
 *
 * - The media-cast-button currently doesn't work with the `hls-video` player.
 *
 * - We don't use media chrome tooltips: Media chrome has mechanism for
 *   statically providing translations but it wasn't working when I tried with
 *   4.9.0. The media chrome tooltips also get clipped for the cornermost
 *   buttons. Finally, the rest of the buttons on this screen don't have a
 *   tooltip either.
 *
 *   Revisit this when we have a custom tooltip element we can then also use on
 *   this screen, which can also be used enhancement for the other buttons on
 *   this screen which use "title" (which get clipped when they are multi-word).
 *
 * - See: [Note: Spurious media chrome resize observer errors]
 *
 * - If something is not working as expected, a possible reason might be the
 *   focus workaround. See: [Note: Media chrome focus workaround].
 */
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

// playsinline will play the video inline on mobile browsers (where the default
// is to open a full screen player).
const livePhotoVideoHTML = (videoURL: string) => `
<video muted playsinline oncontextmenu="return false;">
  <source src="${videoURL}" />
</video>
`;

/**
 * HTML for the bottom controls (caption on left, action buttons on right).
 *
 * The caption uses the line-clamp CSS property, which behaves unexpectedly
 * when we also assign padding to the "p" element on which we're setting the
 * line clamp: the "clipped" lines show through in the padding area.
 *
 * As a workaround, wrap the p in a div. Set the line-clamp on the p, and the
 * padding on the div.
 */
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

/**
 * Truncate caption text to 154 characters.
 *
 * @returns An object with the (possibly truncated) text and a flag indicating
 * whether or not the text was truncated.
 */
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
    // Excess whitespace causes excess DOM nodes, causing our firstChild to not
    // be what we wanted them to be.
    template.innerHTML = htmlString.trim();
    return template.content.firstChild!;
};

/**
 * Update the ARIA attributes for the button that controls the more menu when
 * the menu is closed.
 */
export const resetMoreMenuButtonOnMenuClose = (buttonElement: HTMLElement) => {
    buttonElement.removeAttribute("aria-controls");
    buttonElement.removeAttribute("aria-expanded");
};
