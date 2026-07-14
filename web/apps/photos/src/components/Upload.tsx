// TODO: Audit this file
// TODO: Too many null assertions in this file. The types need reworking.
/* eslint-disable react-hooks/exhaustive-deps */
/* eslint-disable @typescript-eslint/no-misused-promises */
/* eslint-disable @typescript-eslint/no-floating-promises */
import { DefaultOptionsV2 } from "@/components/DefaultOptionsV2";
import { TakeoutOptionsV2 } from "@/components/TakeoutOptionsV2";
import type {
    InProgressUpload,
    SegregatedFinishedUploads,
    UploadBatchResult,
    UploadCounter,
    UploadFileNames,
    UploadItemWithCollection,
} from "@/services/upload-manager";
import {
    favoritedFilesFromUploadBatchResult,
    successfulFilesFromUploadBatchResult,
    uploadManager,
} from "@/services/upload-manager";
import watcher from "@/services/watch";
import { Album02Icon, Folder01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import DiscFullIcon from "@mui/icons-material/DiscFull";
import GoogleIcon from "@mui/icons-material/Google";
import {
    Box,
    CircularProgress,
    Dialog,
    DialogTitle,
    Link,
    Stack,
    styled,
    Typography,
    type DialogProps,
} from "@mui/material";
import type { LocalUser } from "ente-accounts/services/user";
import { isDesktop } from "ente-base/app";
import { SpacedRow } from "ente-base/components/containers";
import { DialogCloseIconButton } from "ente-base/components/mui/DialogCloseIconButton";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { RowButton } from "ente-base/components/RowButton";
import { SingleInputDialog } from "ente-base/components/SingleInputDialog";
import {
    useModalVisibility,
    type ModalVisibilityProps,
} from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import { basename, dirname, joinPath } from "ente-base/file-name";
import log from "ente-base/log";
import type {
    CollectionMapping,
    Electron,
    PreUploadSkippedFile,
    ZipItem,
} from "ente-base/types/ipc";
import type { UploadTypeSelectorIntent } from "ente-gallery/components/Upload";
import { UploadProgressV2 } from "ente-gallery/components/upload-progress-v2/UploadProgressV2";
import { CanvasReadbackBlockedDialog } from "ente-gallery/components/upload/CanvasReadbackBlockedDialog";
import { UploadProgress } from "ente-gallery/components/UploadProgress";
import { useFileInput } from "ente-gallery/components/utils/use-file-input";
import {
    groupItemsBasedOnParentFolder,
    takeoutAlbumMetadataJSONItemForFolder,
    uploadPathPrefix,
    type FileAndPath,
    type UploadItem,
    type UploadItemAndPath,
    type UploadPhase,
} from "ente-gallery/services/upload";
import {
    tryParseTakeoutAlbumNameMetadataJSON,
    type ParsedMetadataJSON,
} from "ente-gallery/services/upload/metadata-json";
import {
    sessionExpiredErrorMessage,
    storageLimitExceededErrorMessage,
    subscriptionExpiredErrorMessage,
} from "ente-gallery/services/upload/upload-service";
import { hasReliableCanvasReadback } from "ente-gallery/utils/upload/canvas-integrity";
import { CollectionSubType, type Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { CollectionMappingChoice } from "ente-new/photos/components/CollectionMappingChoice";
import type { CollectionSelectorAttributes } from "ente-new/photos/components/CollectionSelector";
import type { RemotePullOpts } from "ente-new/photos/components/gallery";
import { downloadAppDialogAttributes } from "ente-new/photos/components/utils/download";
import { useSettingsSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import { suppressAutoLockOnBlurForTrustedPrompt } from "ente-new/photos/services/app-lock";
import {
    addOrCopyToCollection,
    addToFavoritesCollection,
    canAddFilesToCollection,
    canDirectlyUploadToCollection,
    createAlbum,
    createHiddenAlbum,
    isHiddenCollection,
    savedAllCollections,
    savedHiddenCollections,
    savedNormalCollections,
    savedOrCreateUserUncategorizedCollection,
} from "ente-new/photos/services/collection";
import { redirectToCustomerPortal } from "ente-new/photos/services/user-details";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { firstNonEmpty } from "ente-utils/array";
import { t } from "i18next";
import React, { useCallback, useEffect, useRef, useState } from "react";

interface UploadProps {
    /** The logged in user, if any. */
    user?: LocalUser;
    isFirstUpload?: boolean;
    uploadTypeSelectorView: boolean;
    dragAndDropFiles: File[];
    uploadTypeSelectorIntent: UploadTypeSelectorIntent;
    activeCollection?: Collection;
    closeUploadTypeSelector: () => void;
    setLoading: (loading: boolean) => void;
    setShouldDisableDropzone: (value: boolean) => void;
    showCollectionSelector?: () => void;
    /**
     * Called when the uploader (or the file watcher) wants to perform a full
     * remote pull.
     *
     * See also {@link onRemoteFilesPull}.
     */
    onRemotePull: (opts?: RemotePullOpts) => Promise<void>;
    /**
     * Called when an action in the uploader requires us to first pull the
     * latest files and collections from remote.
     *
     * See: [Note: Full remote pull vs files pull]
     *
     * Specifically, this is used prior to creating a new album, to obtain
     * (potential) existing albums from remote so that they can be matched by
     * name if needed.
     */
    onRemoteFilesPull: () => Promise<void>;
    /**
     * Show the collection selector with the given {@link attributes}.
     */
    onOpenCollectionSelector?: (
        attributes: CollectionSelectorAttributes,
    ) => void;
    /**
     * Close the collection selector if it is open.
     */
    onCloseCollectionSelector?: () => void;
    /**
     * Callback invoked when a file is uploaded.
     *
     * @param file The newly uploaded file.
     */
    onUploadFile: (file: EnteFile) => void;
    /** Called when the plan selection modal should be shown. */
    onShowPlanSelector?: () => void;
    /**
     * Called when the upload failed because the user's session has expired, and
     * the Upload component wants to prompt the user to log in again.
     */
    onShowSessionExpiredDialog: () => void;
    /**
     * If true, the upload is being initiated from the hidden albums section.
     *
     * When set, the collection selector will only show hidden albums, and any
     * new albums created will be hidden albums.
     */
    isInHiddenSection?: boolean;
}

type UploadType = "files" | "folders" | "zips";

interface UploadFilesOptions {
    persistPendingUploads?: boolean;
    postUploadTargetCollection?: Collection;
}

/**
 * Top level component that houses the infrastructure for handling uploads.
 */
export const Upload: React.FC<UploadProps> = ({
    user,
    isFirstUpload,
    dragAndDropFiles,
    onRemotePull,
    onRemoteFilesPull,
    onOpenCollectionSelector,
    onCloseCollectionSelector,
    onUploadFile,
    onShowPlanSelector,
    onShowSessionExpiredDialog,
    ...props
}) => {
    const { showMiniDialog, onGenericError } = useBaseContext();
    const { showNotification, watchFolderView } = usePhotosAppContext();
    const { isInternalUser } = useSettingsSnapshot();
    const enableUploadProgressUIV2 = isInternalUser;

    const [uploadProgressView, setUploadProgressView] = useState(false);
    const [
        showCanvasReadbackBlockedDialog,
        setShowCanvasReadbackBlockedDialog,
    ] = useState(false);
    const [uploadPhase, setUploadPhase] = useState<UploadPhase>("preparing");
    const [uploadFileNames, setUploadFileNames] = useState<UploadFileNames>();
    const [uploadCounter, setUploadCounter] = useState<UploadCounter>({
        finished: 0,
        total: 0,
    });
    const [inProgressUploads, setInProgressUploads] = useState(
        new Array<InProgressUpload>(),
    );
    const [finishedUploads, setFinishedUploads] =
        useState<SegregatedFinishedUploads>(new Map());
    const [percentComplete, setPercentComplete] = useState(0);
    const [hasLivePhotos, setHasLivePhotos] = useState(false);
    const [prefilledNewAlbumName, setPrefilledNewAlbumName] = useState("");

    const [openCollectionMappingChoice, setOpenCollectionMappingChoice] =
        useState(false);
    const [importSuggestion, setImportSuggestion] = useState<ImportSuggestion>(
        defaultImportSuggestion,
    );
    const {
        show: showNewAlbumNameInput,
        props: newAlbumNameInputVisibilityProps,
    } = useModalVisibility();

    /**
     * {@link File}s that the user drag-dropped or selected for uploads (web).
     *
     * This is the only type of selection that is possible when we're running in
     * the browser.
     */
    const [webFiles, setWebFiles] = useState<File[]>([]);
    /**
     * {@link File}s that the user drag-dropped or selected for uploads,
     * augmented with their paths (desktop).
     *
     * These siblings of {@link webFiles} come into play when we are running in
     * the context of our desktop app.
     */
    const [desktopFiles, setDesktopFiles] = useState<FileAndPath[]>([]);
    /**
     * Paths of file to upload that we've received over the IPC bridge from the
     * code running in the Node.js layer of our desktop app.
     *
     * Unlike {@link filesWithPaths} which are still user initiated,
     * {@link desktopFilePaths} can be set via programmatic action. For example,
     * if the user has setup a folder watch, and a new file is added on their
     * local file system in one of the watched folders, then the relevant path
     * of the new file would get added to {@link desktopFilePaths}.
     */
    const [desktopFilePaths, setDesktopFilePaths] = useState<string[]>([]);
    /**
     * (zip file path, entry within zip file) tuples for zip files that the user
     * is trying to upload.
     *
     * These are only set when we are running in the context of our desktop app.
     * They may be set either on a user action (when the user selects or
     * drag-drops zip files) or programmatically (when the app is trying to
     * resume pending uploads from a previous session).
     */
    const [desktopZipItems, setDesktopZipItems] = useState<ZipItem[]>([]);

    const [preUploadSkippedFiles, setPreUploadSkippedFiles] = useState<
        PreUploadSkippedFile[]
    >([]);

    /**
     * Consolidated and cleaned list obtained from {@link webFiles},
     * {@link desktopFiles}, {@link desktopFilePaths} and
     * {@link desktopZipItems}.
     *
     * Augment each {@link UploadItem} with its "path" (relative path or name in
     * the case of {@link webFiles}, absolute path in the case of
     * {@link desktopFiles}, {@link desktopFilePaths}, and the path within the
     * zip file for {@link desktopZipItems}).
     *
     * See the documentation of {@link UploadItem} for more details.
     */
    const uploadItemsAndPaths = useRef<UploadItemAndPath[]>([]);

    /**
     * If true, then the next upload we'll be processing was initiated by our
     * desktop app.
     */
    const isPendingDesktopUpload = useRef(false);

    /**
     * If set, this will be the name of the collection that our desktop app
     * wishes for us to upload into.
     */
    const pendingDesktopUploadCollectionName = useRef<string | undefined>(
        undefined,
    );

    /**
     * This is set to thue user's choice when the user chooses one of the
     * predefined type to upload from the upload type selector dialog
     */
    const selectedUploadType = useRef<UploadType | undefined>(undefined);

    const currentUploadPromise = useRef<Promise<void> | undefined>(undefined);
    const uploadRunning = useRef(false);
    const isDragAndDrop = useRef(false);

    /**
     * Used to remember a deferred "real destination" collectionf or the current upload flow.
     * So this ref remembers the original shared album target across failed uploads.
     */
    const retrySharedAlbumUploadTarget = useRef<Collection | undefined>(
        undefined,
    );

    /**
     * `true` if we've activated one hidden {@link Inputs} that allow the user
     * to select items, and haven't heard back from the browser as to the
     * selection (or cancellation).
     *
     * [Note: Showing an activity indicator during upload item selection]
     *
     * When selecting a large number of items (100K+), the browser can take
     * significant time (10s+) before it hands back control to us. The
     * {@link isInputPending} state tracks this intermediate state, and we use
     * it to show an activity indicator to let that the user know that their
     * selection is still being processed.
     */
    const [isInputPending, setIsInputPending] = useState(false);

    /**
     * Files that were selected by the user in the last activation of one of the
     * hidden {@link Inputs}.
     */
    const [selectedInputFiles, setSelectedInputFiles] = useState<File[]>([]);

    const handleInputSelect = useCallback((files: File[]) => {
        setIsInputPending(false);
        setSelectedInputFiles(files);
    }, []);

    const handleInputCancel = useCallback(() => {
        setIsInputPending(false);
    }, []);

    const {
        getInputProps: getFileSelectorInputProps,
        openSelector: openFileSelector,
    } = useFileInput({
        directory: false,
        onSelect: handleInputSelect,
        onCancel: handleInputCancel,
    });

    const {
        getInputProps: getFolderSelectorInputProps,
        openSelector: openFolderSelector,
    } = useFileInput({
        directory: true,
        onSelect: handleInputSelect,
        onCancel: handleInputCancel,
    });

    const {
        getInputProps: getZipFileSelectorInputProps,
        openSelector: openZipFileSelector,
    } = useFileInput({
        directory: false,
        accept: ".zip",
        onSelect: handleInputSelect,
        onCancel: handleInputCancel,
    });

    const electron = globalThis.electron;

    const closeUploadProgress = () => uploadManager.hideUploadProgressDialog();

    const handleCollectionMappingChoiceClose = () => {
        setOpenCollectionMappingChoice(false);
        uploadRunning.current = false;
    };

    const handleCollectionSelectorCancel = () => {
        uploadRunning.current = false;
        retrySharedAlbumUploadTarget.current = undefined;
    };

    useEffect(() => {
        uploadManager.init(
            {
                setPercentComplete,
                setUploadCounter,
                setInProgressUploads,
                setFinishedUploads,
                setUploadPhase,
                // eslint-disable-next-line @typescript-eslint/ban-ts-comment
                // @ts-ignore
                setUploadFilenames: setUploadFileNames,
                setHasLivePhotos,
                setUploadProgressView,
            },
            onUploadFile,
        );

        if (uploadManager.isUploadRunning()) {
            uploadManager.showUploadProgressDialog();
        }

        if (electron) {
            const upload = (collectionName: string, filePaths: string[]) => {
                isPendingDesktopUpload.current = true;
                pendingDesktopUploadCollectionName.current = collectionName;
                setDesktopFilePaths(filePaths);
            };

            watcher.init(
                upload,
                () => void onRemotePull({ source: "watcher-upload" }),
            );

            electron.pendingUploads().then((pending) => {
                if (!pending) return;

                const {
                    collectionName,
                    filePaths,
                    zipItems,
                    preUploadSkippedFiles,
                } = pending;

                log.info(
                    `Resuming pending of upload of ${filePaths.length + zipItems.length} items${collectionName ? " to collection " + collectionName : ""}`,
                );
                isPendingDesktopUpload.current = true;
                pendingDesktopUploadCollectionName.current = collectionName;
                setDesktopFilePaths(filePaths);
                setDesktopZipItems(zipItems);
                setPreUploadSkippedFiles(preUploadSkippedFiles ?? []);
            });
        }
    }, []);

    // Handle selected files when user selects files for upload through the open
    // file / open folder selection dialog, or drag-and-drops them.
    useEffect(() => {
        if (watchFolderView) {
            // if watch folder dialog is open don't catch the dropped file
            // as they are folder being dropped for watching
            return;
        }

        let files: File[];
        isDragAndDrop.current = false;

        switch (selectedUploadType.current) {
            case "files":
            case "folders":
            case "zips":
                files = selectedInputFiles;
                break;

            default:
                isDragAndDrop.current = true;
                files = dragAndDropFiles;
                break;
        }

        if (electron) {
            desktopFilesAndZipItems(electron, files).then(
                ({ fileAndPaths, zipItems, preUploadSkippedFiles }) => {
                    setDesktopFiles(fileAndPaths);
                    setDesktopZipItems(zipItems);
                    setPreUploadSkippedFiles(preUploadSkippedFiles);
                },
            );
        } else {
            setPreUploadSkippedFiles([]);
            setWebFiles(files);
        }
    }, [selectedInputFiles, dragAndDropFiles]);

    // Trigger an upload when any of the dependencies change.
    useEffect(() => {
        // About the paths:
        //
        // - These are not necessarily the full paths. In particular, when
        //   running on the browser they'll be the relative paths (at best) or
        //   just the file-name otherwise.
        //
        // - All the paths use POSIX separators. See inline comments.
        //
        // - For zips we concatenate the path of the zip to the path within the
        //   zip for the purpose of computing the nesting.
        const allItemAndPaths = [
            // Relative path (using POSIX separators) or the file's name.
            webFiles.map((f) => [f, pathLikeForWebFile(f)]),
            // The paths we get from the desktop app all eventually come either
            // from electron.selectDirectory or electron.pathForFile, both of
            // which return POSIX paths.
            desktopFiles.map((fp) => [fp, fp.path]),
            desktopFilePaths.map((p) => [p, p]),
            // Concatenate the path of the item within the zip to path of the
            // zip. This won't affect the upload: this path is only used for
            // computation of the "parent" folder, and this concatenation best
            // reflects the nesting.
            //
            // Re POSIXness: The first path, that of the zip file itself, is
            // POSIX like the other paths we get over the IPC boundary. And the
            // second path, ze[1], the entry name, uses POSIX separators because
            // that is what the ZIP format uses.
            desktopZipItems.map((ze) => [ze, joinPath(dirname(ze[0]), ze[1])]),
        ].flat() as UploadItemAndPath[];

        const hiddenFiles: PreUploadSkippedFile[] = [];
        const prunedItemAndPaths = allItemAndPaths.filter(([, p]) => {
            const name = basename(p);
            if (name.startsWith(".")) {
                hiddenFiles.push({ name, type: "hiddenFile" });
                return false;
            }
            return true;
        });
        const nextPreUploadSkippedFiles =
            preUploadSkippedFiles.concat(hiddenFiles);
        if (hiddenFiles.length > 0)
            setPreUploadSkippedFiles(nextPreUploadSkippedFiles);

        if (prunedItemAndPaths.length == 0) {
            if (
                nextPreUploadSkippedFiles.length > 0 &&
                !uploadRunning.current
            ) {
                uploadManager.prepareForNewUpload();
                setUploadPhase("done");
                uploadManager.showUploadProgressDialog();
            }
            return;
        }

        if (uploadManager.isUploadRunning()) {
            if (watcher.isUploadRunning()) {
                log.info("Pausing watch folder sync to prioritize user upload");
                watcher.pauseRunningSync();
            } else {
                log.info(
                    "Ignoring new upload request when upload is already running",
                );
                return;
            }
        }

        if (!electron && !hasReliableCanvasReadback()) {
            log.warn("Canvas readback integrity check failed; blocking upload");
            setWebFiles([]);
            selectedUploadType.current = undefined;
            setShowCanvasReadbackBlockedDialog(true);
            return;
        }

        uploadRunning.current = true;
        props.closeUploadTypeSelector();
        props.setLoading(true);

        setWebFiles([]);
        setDesktopFiles([]);
        setDesktopFilePaths([]);
        setDesktopZipItems([]);

        uploadItemsAndPaths.current = prunedItemAndPaths;

        void (async () => {
            const _selectedUploadType = selectedUploadType.current;
            selectedUploadType.current = undefined;
            const _isDragAndDrop = isDragAndDrop.current;
            isDragAndDrop.current = false;

            const importSuggestion = await deriveImportSuggestion(
                _selectedUploadType,
                prunedItemAndPaths,
            );

            if (uploadItemsAndPaths.current !== prunedItemAndPaths) return;

            setImportSuggestion(importSuggestion);

            log.debug(() => ["Upload request", uploadItemsAndPaths.current]);
            log.debug(() => ["Import suggestion", importSuggestion]);

            props.setLoading(false);

            if (isPendingDesktopUpload.current) {
                isPendingDesktopUpload.current = false;
                if (pendingDesktopUploadCollectionName.current) {
                    // Include hidden collections so watch folder syncs add
                    // files to existing hidden albums instead of creating new
                    // visible ones
                    uploadFilesToNewCollections(
                        "root",
                        pendingDesktopUploadCollectionName.current,
                        true,
                    );
                    pendingDesktopUploadCollectionName.current = undefined;
                } else {
                    uploadFilesToNewCollections("parent", undefined, true);
                }
                return;
            }

            if (electron && _selectedUploadType == "zips") {
                uploadFilesToNewCollections("parent");
                return;
            }

            if (isFirstUpload && !importSuggestion.rootFolderName) {
                importSuggestion.rootFolderName = t(
                    "autogenerated_first_album_name",
                );
            }

            if (_isDragAndDrop) {
                const canUploadToActiveCollection =
                    props.activeCollection &&
                    (props.activeCollection.owner.id == user?.id ||
                        canAddFilesToCollection(props.activeCollection));
                if (props.activeCollection && canUploadToActiveCollection) {
                    uploadFilesToExistingCollection(
                        props.activeCollection,
                        prunedItemAndPaths,
                    );
                    return;
                }
            }

            const showNextModal = importSuggestion.hasNestedFolders
                ? () => setOpenCollectionMappingChoice(true)
                : () => {
                      setPrefilledNewAlbumName(importSuggestion.rootFolderName);
                      showNewAlbumNameInput();
                  };

            onOpenCollectionSelector?.({
                action: "upload",
                activeCollectionID: props.activeCollection?.id,
                showHiddenCollections: props.isInHiddenSection,
                onSelectCollection: (collection) =>
                    uploadFilesToExistingCollection(
                        collection,
                        prunedItemAndPaths,
                    ),
                onCreateCollection: showNextModal,
                onCancel: handleCollectionSelectorCancel,
            });
        })();
    }, [webFiles, desktopFiles, desktopFilePaths, desktopZipItems]);

    const preCollectionCreationAction = () => {
        onCloseCollectionSelector?.();
        props.setShouldDisableDropzone(uploadManager.isUploadInProgress());
        setUploadPhase("preparing");
        uploadManager.showUploadProgressDialog();
    };

    /**
     *
     * @param batchResult
     * @param targetCollection
     *
     * This function actually receives the batchResult which is the post-upload
     * object and the target collection of upload.
     *
     * the {@link successfulFilesFromUploadBatchResult} take the batchResult
     * and then returns an array of files which is of the type {@link EnteFile}
     * this file is then added to the corresponding shared album.
     */
    const handlePostUploadBatchResult = async (
        batchResult: UploadBatchResult,
        targetCollection: Collection | undefined,
    ) => {
        if (!targetCollection) return;

        const uploadedFiles = successfulFilesFromUploadBatchResult(batchResult);
        if (!uploadedFiles.length) return;

        log.info(
            `Adding ${uploadedFiles.length} uploaded file(s) to post-upload target collection ${targetCollection.id}`,
        );
        try {
            await addOrCopyToCollection(targetCollection, uploadedFiles);
            log.info(
                `Added ${uploadedFiles.length} uploaded file(s) to post-upload target collection ${targetCollection.id}`,
            );
        } catch (e) {
            log.error(
                `Failed to add ${uploadedFiles.length} uploaded file(s) to post-upload target collection ${targetCollection.id}`,
                e,
            );
            throw e;
        }
    };

    /**
     *
     * @param batchResult
     * @param postUploadTargetCollection
     * @returns
     *
     * Adds successfully uploaded Takeout-favorited files to Favorites, skipping
     * files whose effective target collection is hidden.
     */
    const handleTakeoutFavoritesPostUpload = async (
        batchResult: UploadBatchResult,
        postUploadTargetCollection: Collection | undefined,
    ) => {
        // Checking if any of the uploaded items have their takeoutFavorited as true.
        if (
            !batchResult.itemResults.some(
                ({ takeoutFavorited }) => takeoutFavorited,
            )
        ) {
            return;
        }

        // Get the list of IDs of hidden collections.
        const hiddenCollectionIDs = new Set(
            (await savedHiddenCollections()).map(({ id }) => id),
        );

        // In some cases, such as when the upload is happening to a non-owned album,
        // files are first added to the user's own album and then, after upload,
        // linked to the shared album.
        //
        // For such cases, check whether the real intended upload location is a
        // hidden album and add it to the set.
        if (
            postUploadTargetCollection &&
            isHiddenCollection(postUploadTargetCollection)
        ) {
            hiddenCollectionIDs.add(postUploadTargetCollection.id);
        }

        /**
         * Treating the requestCollectionID as a hidden album because the upload was
         * initated from the hidden-albums UI.
         *
         * savedHiddenCollections will already include hidden collections, but it is not
         * guaranteed to include every hidden album. So this is also a guard at the UI
         * level.
         */
        if (props.isInHiddenSection) {
            for (const { requestedCollectionID } of batchResult.itemResults) {
                hiddenCollectionIDs.add(requestedCollectionID);
            }
        }
        const favoritedFiles = favoritedFilesFromUploadBatchResult(
            batchResult,
            hiddenCollectionIDs,
            postUploadTargetCollection?.id,
        );
        if (!favoritedFiles.length) return;

        log.info(
            `Adding ${favoritedFiles.length} Google Takeout favorite file(s) to Favorites`,
        );
        try {
            await addToFavoritesCollection(favoritedFiles);
            log.info(
                `Added ${favoritedFiles.length} Google Takeout favorite file(s) to Favorites`,
            );
        } catch (e) {
            log.error(
                `Failed to import ${favoritedFiles.length} Google Takeout favorite file(s)`,
                e,
            );
        }
    };

    const resetUploadUIState = () => {
        props.setShouldDisableDropzone(false);
        uploadRunning.current = false;
    };

    const uploadFilesToExistingCollection = async (
        collection: Collection,
        uploadItemAndPaths: UploadItemAndPath[],
    ) => {
        preCollectionCreationAction();
        try {
            const uploadCollection = canDirectlyUploadToCollection(collection)
                ? collection
                : canAddFilesToCollection(collection)
                  ? await savedOrCreateUserUncategorizedCollection()
                  : undefined;

            if (!uploadCollection) {
                throw new Error("Upload not allowed for the selected album");
            }

            const uploadItemsWithCollection = uploadItemAndPaths.map(
                ([uploadItem, path], index) => ({
                    uploadItem,
                    pathPrefix: uploadPathPrefix(path),
                    localID: index,
                    collectionID: uploadCollection.id,
                }),
            );
            await waitInQueueAndUploadFiles(
                uploadItemsWithCollection,
                [uploadCollection],
                {
                    persistPendingUploads: uploadCollection.id == collection.id,
                    postUploadTargetCollection:
                        uploadCollection.id == collection.id
                            ? undefined
                            : collection,
                },
            );
            if (uploadItemsAndPaths.current === uploadItemAndPaths) {
                uploadItemsAndPaths.current = [];
            }
        } catch (e) {
            retrySharedAlbumUploadTarget.current = undefined;
            closeUploadProgress();
            resetUploadUIState();
            onGenericError(e);
        }
    };

    const uploadFilesToNewCollections = async (
        mapping: CollectionMapping,
        collectionName?: string,
        includeHiddenCollections?: boolean,
        createHidden?: boolean,
    ) => {
        preCollectionCreationAction();
        let uploadItemsWithCollection: UploadItemWithCollection[] = [];
        let collectionNameToUploadItems = new Map<
            string,
            UploadItemAndPath[]
        >();
        if (mapping == "root") {
            collectionNameToUploadItems.set(
                // Un-enforced convention is that collectionName is always set
                // when mapping is "root". TODO: Reflect this in types.
                collectionName!,
                uploadItemsAndPaths.current,
            );
        } else {
            collectionNameToUploadItems = await groupItemsBasedOnParentFolder(
                uploadItemsAndPaths.current,
                collectionName,
            );
        }
        const collections: Collection[] = [];
        try {
            await onRemoteFilesPull();
            // When uploading to hidden section (createHidden), only search
            // hidden collections. When syncing from watch folders
            // (includeHiddenCollections), search all collections so files go
            // to existing albums regardless of visibility. Otherwise, search
            // only normal (visible) collections.
            const existingCollections = createHidden
                ? await savedHiddenCollections()
                : includeHiddenCollections
                  ? await savedAllCollections()
                  : await savedNormalCollections();
            let index = 0;
            for (const [
                collectionName,
                uploadItems,
            ] of collectionNameToUploadItems) {
                const collection = await matchExistingOrCreateAlbum(
                    collectionName,
                    user!,
                    existingCollections,
                    createHidden,
                );
                collections.push(collection);
                uploadItemsWithCollection = [
                    ...uploadItemsWithCollection,
                    ...uploadItems.map(([uploadItem, path]) => ({
                        localID: index++,
                        pathPrefix: uploadPathPrefix(path),
                        collectionID: collection.id,
                        uploadItem,
                    })),
                ];
            }
        } catch (e) {
            retrySharedAlbumUploadTarget.current = undefined;
            closeUploadProgress();
            resetUploadUIState();
            onGenericError(e);
            return;
        }
        await waitInQueueAndUploadFiles(
            uploadItemsWithCollection,
            collections,
            {
                persistPendingUploads: true,
                postUploadTargetCollection: undefined,
            },
        );
        uploadItemsAndPaths.current = [];
    };

    const waitInQueueAndUploadFiles = async (
        uploadItemsWithCollection: UploadItemWithCollection[],
        collections: Collection[],
        opts?: UploadFilesOptions,
    ) => {
        const currentPromise = currentUploadPromise.current;
        currentUploadPromise.current = (async () => {
            if (currentPromise) await currentPromise;
            return uploadFiles(uploadItemsWithCollection, collections, opts);
        })();
        await currentUploadPromise.current;
    };

    const preUploadAction = async (
        parsedMetadataJSONMap?: Map<string, ParsedMetadataJSON>,
    ) => {
        uploadManager.prepareForNewUpload(parsedMetadataJSONMap);
        uploadManager.showUploadProgressDialog();
        await onRemotePull({ silent: true, source: "pre-upload" });
    };

    function postUploadAction() {
        resetUploadUIState();
        void onRemotePull({ source: "post-upload" });
    }

    const uploadFiles = async (
        uploadItemsWithCollection: UploadItemWithCollection[],
        collections: Collection[],
        opts?: UploadFilesOptions,
    ) => {
        try {
            retrySharedAlbumUploadTarget.current =
                opts?.postUploadTargetCollection;
            await preUploadAction();
            if (
                opts?.persistPendingUploads &&
                electron &&
                !isPendingDesktopUpload.current &&
                !watcher.isUploadRunning()
            ) {
                setPendingUploads(
                    electron,
                    collections,
                    uploadItemsWithCollection
                        .map(({ uploadItem }) => uploadItem)
                        .filter((x) => x !== undefined),
                    preUploadSkippedFiles,
                );
            }
            const batchResult = await uploadManager.uploadItems(
                uploadItemsWithCollection,
                collections,
                {
                    skipDuplicateAddToUploadCollection:
                        !!opts?.postUploadTargetCollection,
                },
            );
            if (!batchResult.processedAny) closeUploadProgress();
            await handlePostUploadBatchResult(
                batchResult,
                opts?.postUploadTargetCollection,
            );
            await handleTakeoutFavoritesPostUpload(
                batchResult,
                opts?.postUploadTargetCollection,
            );
            if (isDesktop) {
                if (watcher.isUploadRunning()) {
                    await watcher.allFileUploadsDone(uploadItemsWithCollection);
                } else if (watcher.isSyncPaused()) {
                    // Resume folder watch after the user upload that
                    // interrupted it is done.
                    watcher.resumePausedSync();
                }
            }
        } catch (e) {
            log.error("Failed to upload files", e);
            closeUploadProgress();
            notifyUser(e);
        } finally {
            postUploadAction();
        }
    };

    const retryFailed = async () => {
        try {
            log.info("Retrying failed uploads");
            const { items, collections, parsedMetadataJSONMap } =
                uploadManager.failedItemState();
            await preUploadAction(parsedMetadataJSONMap);
            const batchResult = await uploadManager.uploadItems(
                items,
                collections,
                {
                    skipDuplicateAddToUploadCollection:
                        !!retrySharedAlbumUploadTarget.current,
                },
            );
            if (!batchResult.processedAny) closeUploadProgress();
            await handlePostUploadBatchResult(
                batchResult,
                retrySharedAlbumUploadTarget.current,
            );
            await handleTakeoutFavoritesPostUpload(
                batchResult,
                retrySharedAlbumUploadTarget.current,
            );
        } catch (e) {
            log.error("Retrying failed uploads failed", e);
            closeUploadProgress();
            notifyUser(e);
        } finally {
            postUploadAction();
        }
    };

    const notifyUser = (e: unknown) => {
        switch (e instanceof Error && e.message) {
            case sessionExpiredErrorMessage:
                onShowSessionExpiredDialog();
                break;
            case subscriptionExpiredErrorMessage:
                showNotification({
                    color: "critical",
                    captionFirst: true,
                    caption: t("subscription_expired"),
                    title: t("renew_now"),
                    onClick: redirectToCustomerPortal,
                });
                break;
            case storageLimitExceededErrorMessage:
                showNotification({
                    color: "critical",
                    captionFirst: true,
                    caption: t("storage_quota_exceeded"),
                    title: t("upgrade_now"),
                    onClick: onShowPlanSelector,
                    startIcon: <DiscFullIcon />,
                });
                break;
            default:
                showNotification({
                    color: "critical",
                    title: t("generic_error_retry"),
                });
        }
    };

    const uploadToSingleNewCollection = (collectionName: string) => {
        uploadFilesToNewCollections(
            "root",
            collectionName,
            undefined,
            props.isInHiddenSection,
        );
    };

    const cancelUploads = () => {
        uploadManager.cancelRunningUpload();
    };

    const handleUploadTypeSelect = (type: UploadType) => {
        selectedUploadType.current = type;
        // Opening native file/folder pickers can blur the app window on
        // desktop; suppress blur-triggered app lock for this trusted flow.
        if (electron) {
            suppressAutoLockOnBlurForTrustedPrompt();
        }
        setIsInputPending(true);
        switch (type) {
            case "files":
                openFileSelector();
                break;
            case "folders":
                openFolderSelector();
                break;
            case "zips":
                if (electron) {
                    openZipFileSelector();
                } else {
                    showMiniDialog(downloadAppDialogAttributes());
                }
                break;
        }
    };

    const handleCollectionMappingSelect = (mapping: CollectionMapping) =>
        uploadFilesToNewCollections(
            mapping,
            importSuggestion.rootFolderName ||
                t("autogenerated_default_album_name"),
            undefined,
            props.isInHiddenSection,
        );

    return (
        <>
            <Inputs
                {...{
                    getFileSelectorInputProps,
                    getFolderSelectorInputProps,
                    getZipFileSelectorInputProps,
                }}
            />
            <CollectionMappingChoice
                open={openCollectionMappingChoice}
                onClose={handleCollectionMappingChoiceClose}
                onSelect={handleCollectionMappingSelect}
            />
            <UploadTypeSelector
                open={props.uploadTypeSelectorView}
                onClose={props.closeUploadTypeSelector}
                intent={props.uploadTypeSelectorIntent}
                {...{ isInternalUser }}
                pendingUploadType={
                    isInputPending ? selectedUploadType.current : undefined
                }
                onSelect={handleUploadTypeSelect}
            />
            {enableUploadProgressUIV2 ? (
                <UploadProgressV2
                    open={uploadProgressView}
                    onClose={closeUploadProgress}
                    percentComplete={percentComplete}
                    uploadFileNames={uploadFileNames!}
                    uploadCounter={uploadCounter}
                    uploadPhase={uploadPhase}
                    inProgressUploads={inProgressUploads}
                    hasLivePhotos={hasLivePhotos}
                    retryFailed={retryFailed}
                    finishedUploads={finishedUploads}
                    preUploadSkippedFiles={preUploadSkippedFiles}
                    cancelUploads={cancelUploads}
                />
            ) : (
                <UploadProgress
                    open={uploadProgressView}
                    onClose={closeUploadProgress}
                    percentComplete={percentComplete}
                    uploadFileNames={uploadFileNames!}
                    uploadCounter={uploadCounter}
                    uploadPhase={uploadPhase}
                    inProgressUploads={inProgressUploads}
                    hasLivePhotos={hasLivePhotos}
                    retryFailed={retryFailed}
                    finishedUploads={finishedUploads}
                    preUploadSkippedFiles={preUploadSkippedFiles}
                    cancelUploads={cancelUploads}
                />
            )}
            <CanvasReadbackBlockedDialog
                open={showCanvasReadbackBlockedDialog}
                onClose={() => setShowCanvasReadbackBlockedDialog(false)}
            />
            <SingleInputDialog
                {...newAlbumNameInputVisibilityProps}
                title={t("new_album")}
                label={t("album_name")}
                initialValue={prefilledNewAlbumName}
                submitButtonTitle={t("create")}
                onSubmit={uploadToSingleNewCollection}
            />
        </>
    );
};

type GetInputProps = () => React.HTMLAttributes<HTMLInputElement>;

interface InputsProps {
    getFileSelectorInputProps: GetInputProps;
    getFolderSelectorInputProps: GetInputProps;
    getZipFileSelectorInputProps: GetInputProps;
}

/**
 * Create a bunch of HTML inputs elements, one each for the given props.
 *
 * These hidden input element serve as the way for us to show various file /
 * folder Selector dialogs and handle drag and drop inputs.
 */
const Inputs: React.FC<InputsProps> = ({
    getFileSelectorInputProps,
    getFolderSelectorInputProps,
    getZipFileSelectorInputProps,
}) => (
    <>
        <input {...getFileSelectorInputProps()} />
        <input {...getFolderSelectorInputProps()} />
        <input {...getZipFileSelectorInputProps()} />
    </>
);

const desktopFilesAndZipItems = async (electron: Electron, files: File[]) => {
    const fileAndPaths: FileAndPath[] = [];
    let zipItems: ZipItem[] = [];
    let preUploadSkippedFiles: PreUploadSkippedFile[] = [];

    for (const file of files) {
        const path = electron.pathForFile(file);

        if (file.name.startsWith(".")) {
            preUploadSkippedFiles.push({ name: file.name, type: "hiddenFile" });
            continue;
        }

        if (file.name.endsWith(".zip")) {
            try {
                const result = await electron.listZipItems(path);
                zipItems = zipItems.concat(result.items);
                preUploadSkippedFiles = preUploadSkippedFiles.concat(
                    result.preUploadSkippedFiles,
                );
            } catch (e) {
                // IPC failure (desktop returns malformed zips as part of
                // the response, so reaching this catch means something
                // more fundamental went wrong).
                log.error("Failed to list zip items", e);
                preUploadSkippedFiles.push({
                    name: file.name,
                    type: "failedZip",
                });
            }
        } else {
            fileAndPaths.push({ file, path });
        }
    }

    return { fileAndPaths, zipItems, preUploadSkippedFiles };
};

/**
 * Return the relative path or name of a File object selected or
 * drag-and-dropped on the web.
 *
 * There are three cases here:
 *
 * 1. If the user selects individual file(s), then the returned File objects
 *    will only have a `name`.
 *
 * 2. If the user selects directory(ies), then the returned File objects will
 *    have a `webkitRelativePath`. For more details, see [Note:
 *    webkitRelativePath]. In particular, these will POSIX separators.
 *
 * 3. If the user drags-and-drops, then the react-dropzone library that we use
 *    will internally convert `webkitRelativePath` to `path`, but otherwise it
 *    behaves same as case 2.
 *    https://github.com/react-dropzone/file-selector/blob/master/src/file.ts#L1214
 */
const pathLikeForWebFile = (file: File): string =>
    firstNonEmpty([
        // We need to check first, since path is not a property of
        // the standard File objects.
        "path" in file && typeof file.path == "string" ? file.path : undefined,
        file.webkitRelativePath,
        file.name,
    ])!;

/**
 * This is used to prompt the user the make upload strategy choice.
 *
 * This is derived from the items that the user selected.
 */
interface ImportSuggestion {
    rootFolderName: string;
    hasNestedFolders: boolean;
}

const defaultImportSuggestion: ImportSuggestion = {
    rootFolderName: "",
    hasNestedFolders: false,
};

interface ImportSuggestionFromPaths extends ImportSuggestion {
    rootFolderPath: string;
}

const deriveImportSuggestionFromPaths = (
    uploadType: UploadType | undefined,
    paths: string[],
): ImportSuggestionFromPaths => {
    if (isDesktop && uploadType == "files") {
        return { ...defaultImportSuggestion, rootFolderPath: "" };
    }

    const separatorCounts = new Map(
        paths.map((s) => [s, s.match(/\//g)?.length ?? 0]),
    );
    const separatorCount = (s: string) => separatorCounts.get(s)!;
    paths.sort((path1, path2) => separatorCount(path1) - separatorCount(path2));
    const firstPath = paths[0]!;
    const lastPath = paths[paths.length - 1]!;

    const L = firstPath.length;
    let i = 0;
    const firstFileFolder = firstPath.substring(0, firstPath.lastIndexOf("/"));
    const lastFileFolder = lastPath.substring(0, lastPath.lastIndexOf("/"));

    while (i < L && firstPath.charAt(i) === lastPath.charAt(i)) i++;
    let commonPathPrefix = firstPath.substring(0, i);
    let rootFolderPath = "";

    if (commonPathPrefix) {
        rootFolderPath = commonPathPrefix.substring(
            0,
            commonPathPrefix.lastIndexOf("/"),
        );
        commonPathPrefix = rootFolderPath;
        if (commonPathPrefix) {
            commonPathPrefix = commonPathPrefix.substring(
                commonPathPrefix.lastIndexOf("/") + 1,
            );
        }
    }

    return {
        rootFolderName: commonPathPrefix || "",
        rootFolderPath,
        hasNestedFolders: firstFileFolder !== lastFileFolder,
    };
};

/**
 *
 * @param uploadType
 * @param uploadItemAndPaths
 * @returns
 *
 * rootFolderName: The name of root folder, if there exist a metadata.json in the
 * same directory which has a valid title we will be using that else will
 * fallback to the directory foldername.
 */
const deriveImportSuggestion = async (
    uploadType: UploadType | undefined,
    uploadItemAndPaths: UploadItemAndPath[],
): Promise<ImportSuggestion> => {
    const suggestion = deriveImportSuggestionFromPaths(
        uploadType,
        uploadItemAndPaths.map(([, path]) => path),
    );

    const albumMetadataJSON = takeoutAlbumMetadataJSONItemForFolder(
        uploadItemAndPaths,
        suggestion.rootFolderPath,
    );

    const albumName = albumMetadataJSON
        ? await tryParseTakeoutAlbumNameMetadataJSON(albumMetadataJSON)
        : undefined;

    return {
        rootFolderName: albumName ?? suggestion.rootFolderName,
        hasNestedFolders: suggestion.hasNestedFolders,
    };
};

const matchExistingOrCreateAlbum = async (
    albumName: string,
    user: LocalUser,
    existingCollections: Collection[],
    createHidden?: boolean,
) => {
    for (const collection of existingCollections) {
        // When creating a hidden album, only match hidden collections.
        // This prevents hidden uploads from going to visible albums.
        if (createHidden && !isHiddenCollection(collection)) continue;

        if (
            // Name matches
            collection.name == albumName &&
            // Valid types
            (collection.type == "album" ||
                collection.type == "folder" ||
                collection.type == "uncategorized") &&
            // Not a quicklink
            collection.magicMetadata?.data.subType !=
                CollectionSubType.quicklink &&
            // Owned by user
            collection.owner.id == user.id
        ) {
            log.info(
                `Found existing album ${albumName} with id ${collection.id}`,
            );
            return collection;
        }
    }

    const collection = createHidden
        ? await createHiddenAlbum(albumName)
        : await createAlbum(albumName);
    log.info(`Created new album ${albumName} with id ${collection.id}`);
    return collection;
};

const setPendingUploads = async (
    electron: Electron,
    collections: Collection[],
    uploadItems: UploadItem[],
    preUploadSkippedFiles: PreUploadSkippedFile[],
) => {
    let collectionName: string | undefined;
    /* collection being one suggest one of two things
        1. Either the user has upload to a single existing collection
        2. Created a new single collection to upload to
            may have had multiple folder, but chose to upload
            to one album
        hence saving the collection name when upload collection count is 1
        helps the info of user choosing this options
        and on next upload we can directly start uploading to this collection
    */
    if (collections.length == 1) {
        collectionName = collections[0]!.name;
    }

    const filePaths: string[] = [];
    const zipItems: ZipItem[] = [];
    for (const item of uploadItems) {
        if (item instanceof File) {
            throw new Error("Unexpected web file for a desktop pending upload");
        } else if (typeof item == "string") {
            filePaths.push(item);
        } else if (Array.isArray(item)) {
            zipItems.push(item);
        } else {
            filePaths.push(item.path);
        }
    }

    await electron.setPendingUploads({
        collectionName,
        filePaths,
        zipItems,
        preUploadSkippedFiles,
    });
};

type UploadTypeSelectorProps = ModalVisibilityProps & {
    /** Whether experimental upload UI should be shown. */
    isInternalUser: boolean;
    /**
     * The particular context / scenario in which this upload is occurring.
     */
    intent: UploadTypeSelectorIntent;
    /**
     * If we're waiting on the user to select items using a previously activated
     * file input, then this will be set to the type of that input.
     */
    pendingUploadType: UploadType | undefined;
    /**
     * Called when the user selects one of the options.
     */
    onSelect: (type: UploadType) => void;
};

/**
 * Request the user to specify which type of file / folder / zip it is that they
 * wish to upload.
 *
 * This selector (and the "Upload" button) is functionally redundant, the user
 * can just drag and drop any of these into the app to directly initiate the
 * upload. But having an explicit easy to reach button is also necessary for new
 * users, or for cases where drag-and-drop might not be appropriate.
 */
const UploadTypeSelector: React.FC<UploadTypeSelectorProps> = ({
    open,
    onClose,
    isInternalUser,
    intent,
    pendingUploadType,
    onSelect,
}) => {
    const handleClose: DialogProps["onClose"] = () => {
        // Disable backdrop clicks and esc keypresses if a selection is pending
        // processing so that the user doesn't inadvertently close the dialog.
        if (pendingUploadType) return;
        onClose();
    };

    return (
        <Dialog
            open={open}
            onClose={handleClose}
            fullWidth
            slotProps={{
                paper: {
                    sx: (theme) => ({
                        maxWidth: "375px",
                        p: 1,
                        borderRadius: "28px",
                        boxShadow: "none",
                        border: "1px solid",
                        borderColor: "stroke.faint",
                        "&:has([data-default-options-v2], [data-takeout-options-v2])":
                            {
                                maxWidth: "621px",
                                p: 0,
                                borderRadius: "20px",
                                backgroundColor: "secondary.main",
                                ...theme.applyStyles("dark", {
                                    backgroundColor: "background.paper",
                                }),
                            },
                        [theme.breakpoints.down(360)]: { p: 0 },
                    }),
                },
            }}
            sx={{
                "& .MuiBackdrop-root": {
                    backgroundColor: "rgba(0, 0, 0, 0.5)",
                },
            }}
        >
            <UploadOptions
                {...{
                    isInternalUser,
                    intent,
                    pendingUploadType,
                    onSelect,
                    onClose,
                }}
            />
        </Dialog>
    );
};

type UploadOptionsProps = Pick<
    UploadTypeSelectorProps,
    "isInternalUser" | "onClose" | "intent" | "pendingUploadType" | "onSelect"
>;

const UploadOptions: React.FC<UploadOptionsProps> = ({
    isInternalUser,
    intent,
    pendingUploadType,
    onSelect,
    onClose,
}) => {
    // [Note: Dialog state remains preserved on reopening]
    //
    // Keep dialog content specific state here, in a separate component, so that
    // this state is not tied to the lifetime of the dialog.
    //
    // If we don't do this, then a MUI dialog retains whatever it was doing when
    // it was last closed. Sometimes that is desirable, but sometimes not, and
    // in the latter cases moving the instance specific state to a child works.

    const [showTakeoutOptions, setShowTakeoutOptions] = useState(false);

    const handleTakeoutClose = () => setShowTakeoutOptions(false);

    const handleSelect = (option: UploadType) => {
        switch (option) {
            case "files":
                onSelect("files");
                break;
            case "folders":
                onSelect("folders");
                break;
            case "zips":
                if (!showTakeoutOptions) {
                    setShowTakeoutOptions(true);
                } else {
                    onSelect("zips");
                }
                break;
        }
    };

    const handleSelectFiles = () => handleSelect("files");
    const handleSelectGooglePhotos = () => handleSelect("zips");
    const handleSelectFolder = () => handleSelect("folders");

    return showTakeoutOptions ? (
        isInternalUser ? (
            <TakeoutOptionsV2
                onBack={handleTakeoutClose}
                onSelectFolder={handleSelectFolder}
                onSelectZips={handleSelectGooglePhotos}
                {...{ onClose }}
            />
        ) : (
            <TakeoutOptions
                onSelect={handleSelect}
                onClose={handleTakeoutClose}
            />
        )
    ) : isInternalUser && intent != "collect" ? (
        <DefaultOptionsV2
            intent={intent}
            isFileSelectionPending={pendingUploadType == "files"}
            isFolderSelectionPending={pendingUploadType == "folders"}
            onSelectFiles={handleSelectFiles}
            onSelectGooglePhotos={handleSelectGooglePhotos}
            onSelectFolder={handleSelectFolder}
            {...{ onClose }}
        />
    ) : (
        <DefaultOptions
            {...{ intent, pendingUploadType, onClose }}
            onSelect={handleSelect}
        />
    );
};

const DefaultOptions: React.FC<
    Pick<
        UploadOptionsProps,
        "intent" | "pendingUploadType" | "onClose" | "onSelect"
    >
> = ({ intent, pendingUploadType, onClose, onSelect }) => {
    return (
        <>
            <SpacedRow>
                <DialogTitle variant="h5">
                    {intent == "collect"
                        ? t("select_photos")
                        : intent == "import"
                          ? t("import")
                          : t("upload")}
                </DialogTitle>
                <DialogCloseIconButton {...{ onClose }} />
            </SpacedRow>
            <Box sx={{ p: "12px", pt: "16px" }}>
                <RoundedButtonStack>
                    {intent != "import" && (
                        <RowButton
                            startIcon={
                                <HugeiconsIcon icon={Album02Icon} size={20} />
                            }
                            endIcon={
                                pendingUploadType == "files" ? (
                                    <PendingIndicator />
                                ) : (
                                    <ChevronRightIcon />
                                )
                            }
                            label={t("files")}
                            onClick={() => onSelect("files")}
                        />
                    )}
                    <RowButton
                        startIcon={
                            <HugeiconsIcon icon={Folder01Icon} size={20} />
                        }
                        endIcon={
                            pendingUploadType == "folders" ? (
                                <PendingIndicator />
                            ) : (
                                <ChevronRightIcon />
                            )
                        }
                        label={t("folder")}
                        onClick={() => onSelect("folders")}
                    />
                    {intent != "collect" && (
                        <RowButton
                            startIcon={<GoogleIcon />}
                            endIcon={<ChevronRightIcon />}
                            label={t("google_takeout")}
                            onClick={() => onSelect("zips")}
                        />
                    )}
                </RoundedButtonStack>
                <Typography
                    sx={{
                        color: "text.muted",
                        p: "12px",
                        pt: "24px",
                        textAlign: "center",
                    }}
                >
                    {t("drag_and_drop_hint")}
                </Typography>
            </Box>
        </>
    );
};

const PendingIndicator = () => (
    <CircularProgress size={18} sx={{ color: "stroke.muted" }} />
);

const TakeoutOptions: React.FC<
    Pick<UploadOptionsProps, "onSelect" | "onClose">
> = ({ onSelect, onClose }) => (
    <>
        <SpacedRow>
            <DialogTitle variant="h5">{t("google_takeout")}</DialogTitle>
            <DialogCloseIconButton {...{ onClose }} />
        </SpacedRow>
        <Stack sx={{ padding: "18px 12px 20px 12px", gap: "16px" }}>
            <Stack sx={{ gap: "8px", "& button": { borderRadius: "16px" } }}>
                <FocusVisibleButton
                    color="accent"
                    fullWidth
                    onClick={() => onSelect("folders")}
                >
                    {t("select_folder")}
                </FocusVisibleButton>
                <FocusVisibleButton
                    color="secondary"
                    fullWidth
                    onClick={() => onSelect("zips")}
                >
                    {t("select_zips")}
                </FocusVisibleButton>
                <Link
                    href="https://ente.com/help/photos/migration/from-google-photos/"
                    target="_blank"
                    rel="noopener"
                >
                    <FocusVisibleButton color="secondary" fullWidth>
                        {t("faq")}
                    </FocusVisibleButton>
                </Link>
            </Stack>
            <Typography variant="small" sx={{ color: "text.muted" }}>
                {t("takeout_hint")}
            </Typography>
        </Stack>
    </>
);

const RoundedButtonStack = styled("div")`
    display: flex;
    flex-direction: column;
    gap: 4px;
    & > button {
        border-radius: 16px;
    }
`;
