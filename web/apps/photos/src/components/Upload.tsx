// TODO: Too many null assertions in this file. The types need reworking.
import { CollectionMappingChoice } from "@/components/CollectionMappingChoice";
import type { CollectionSelectorAttributes } from "@/components/CollectionSelector";
import type { RemotePullOpts } from "@/components/gallery";
import { TakeoutOptions } from "@/components/TakeoutOptions";
import { UploadConfirmationDialog } from "@/components/UploadConfirmationDialog";
import { downloadAppDialogAttributes } from "@/components/utils/download";
import type {
    ImportSource,
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
    uploadableMediaCount,
    uploadManager,
} from "@/services/upload-manager";
import watcher from "@/services/watch";
import DiscFullIcon from "@mui/icons-material/DiscFull";
import { Dialog, type DialogProps } from "@mui/material";
import type { LocalUser } from "ente-accounts/services/user";
import { isDesktop } from "ente-base/app";
import { SingleInputDialog } from "ente-base/components/SingleInputDialog";
import {
    useModalVisibility,
    type ModalVisibilityProps,
} from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import {
    basename,
    dirname,
    joinPath,
    lowercaseExtension,
} from "ente-base/file-name";
import log from "ente-base/log";
import type {
    CollectionMapping,
    Electron,
    PreUploadSkippedFile,
    ZipItem,
} from "ente-base/types/ipc";
import type { UploadTypeSelectorIntent } from "ente-gallery/components/Upload";
import {
    uploadSheetMediaQuery,
    uploadSheetPaperSx,
    useIsUploadSheet,
} from "ente-gallery/components/upload-progress/bottom-sheet";
import { UploadProgress } from "ente-gallery/components/upload-progress/UploadProgress";
import { CanvasReadbackBlockedDialog } from "ente-gallery/components/upload/CanvasReadbackBlockedDialog";
import { DefaultOptions } from "ente-gallery/components/upload/DefaultOptions";
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
import { SlideUpTransition } from "ente-new/photos/components/mui/SlideUpTransition";
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
    onRemotePull: (opts?: RemotePullOpts) => Promise<void>;
    onRemoteFilesPull: () => Promise<void>;
    onOpenCollectionSelector?: (
        attributes: CollectionSelectorAttributes,
    ) => void;
    onCloseCollectionSelector?: () => void;
    onUploadFile: (file: EnteFile) => void;
    onShowPlanSelector?: () => void;
    onShowSessionExpiredDialog: () => void;
    isInHiddenSection?: boolean;
}

type UploadType = "files" | "folders" | "zips";

interface UploadFilesOptions {
    persistPendingUploads?: boolean;
    postUploadTargetCollection?: Collection;
    importTakeoutFavorites?: boolean;
    includePartnerSharedFiles?: boolean;
}

interface NewCollectionsOptions {
    collectionName?: string;
    includeHiddenCollections?: boolean;
    createHidden?: boolean;
    skipConfirmation?: boolean;
    importTakeoutFavorites?: boolean;
    includePartnerSharedFiles?: boolean;
}

type PendingUpload =
    | {
          type: "existing-collection";
          collection: Collection;
          uploadItemAndPaths: UploadItemAndPath[];
      }
    | {
          type: "new-collections";
          uploadItemAndPaths: UploadItemAndPath[];
          collectionNameToUploadItems: Map<string, UploadItemAndPath[]>;
          includeHiddenCollections?: boolean;
          createHidden?: boolean;
      };

interface UploadConfirmation {
    pendingUpload: PendingUpload;
    fileCount: number;
    albumCount: number;
    importSource: ImportSource;
    importFavorites: boolean;
    includePartnerSharedFiles: boolean;
}

type UploadConfirmationState =
    | { phase: "counting"; importSource: ImportSource }
    | ({ phase: "ready" } & UploadConfirmation);

const importSourceHint = (
    uploadItemAndPaths: UploadItemAndPath[],
    isInternalUser: boolean,
): ImportSource =>
    uploadItemAndPaths.some(([, path]) => lowercaseExtension(path) == "json")
        ? "google-takeout"
        : isInternalUser &&
            uploadItemAndPaths.some(
                ([, path]) => lowercaseExtension(path) == "xmp",
            )
          ? "apple-photos"
          : "generic";

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
    const [uploadConfirmation, setUploadConfirmation] = useState<
        UploadConfirmationState | undefined
    >();

    const [openCollectionMappingChoice, setOpenCollectionMappingChoice] =
        useState(false);
    const [importSuggestion, setImportSuggestion] = useState<ImportSuggestion>(
        defaultImportSuggestion,
    );
    const {
        show: showNewAlbumNameInput,
        props: newAlbumNameInputVisibilityProps,
    } = useModalVisibility();
    const didSubmitNewAlbumName = useRef(false);

    const [webFiles, setWebFiles] = useState<File[]>([]);
    const [desktopFiles, setDesktopFiles] = useState<FileAndPath[]>([]);
    const [desktopFilePaths, setDesktopFilePaths] = useState<string[]>([]);
    const [desktopZipItems, setDesktopZipItems] = useState<ZipItem[]>([]);

    const [preUploadSkippedFiles, setPreUploadSkippedFiles] = useState<
        PreUploadSkippedFile[]
    >([]);

    const uploadItemsAndPaths = useRef<UploadItemAndPath[]>([]);

    const isPendingDesktopUpload = useRef(false);

    const pendingDesktopUploadCollectionName = useRef<string | undefined>(
        undefined,
    );
    const pendingDesktopUploadConfirmationOptions = useRef<
        Pick<
            NewCollectionsOptions,
            "importTakeoutFavorites" | "includePartnerSharedFiles"
        >
    >({});

    const selectedUploadType = useRef<UploadType | undefined>(undefined);

    const currentUploadPromise = useRef<Promise<void> | undefined>(undefined);
    const uploadRunning = useRef(false);
    const isDragAndDrop = useRef(false);

    // Preserve the real shared-album destination across retries.
    const retrySharedAlbumUploadTarget = useRef<Collection | undefined>(
        undefined,
    );
    const retryImportTakeoutFavorites = useRef(true);
    const retryIncludePartnerSharedFiles = useRef(true);

    // Browser selection can take over ten seconds for 100k files.
    const [isInputPending, setIsInputPending] = useState(false);

    const [selectedInputFiles, setSelectedInputFiles] = useState<File[]>([]);

    const handleInputSelect = useCallback((files: File[]) => {
        setIsInputPending(false);
        setSelectedInputFiles(files);
    }, []);

    const handleInputCancel = useCallback(() => {
        selectedUploadType.current = undefined;
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
            (file) => {
                if (!watcher.isUploadRunning()) onUploadFile(file);
            },
        );

        if (uploadManager.isUploadRunning()) {
            uploadManager.showUploadProgressDialog();
        }

        if (electron) {
            const upload = (collectionName: string, filePaths: string[]) => {
                isPendingDesktopUpload.current = true;
                pendingDesktopUploadConfirmationOptions.current = {};
                pendingDesktopUploadCollectionName.current = collectionName;
                setDesktopFilePaths(filePaths);
            };

            watcher.init(
                upload,
                () => void onRemotePull({ source: "watcher-upload" }),
            );

            void electron.pendingUploads().then((pending) => {
                if (!pending) return;

                const {
                    collectionName,
                    filePaths,
                    zipItems,
                    preUploadSkippedFiles,
                    importTakeoutFavorites,
                    includePartnerSharedFiles,
                } = pending;

                log.info(
                    `Resuming pending of upload of ${filePaths.length + zipItems.length} items${collectionName ? " to collection " + collectionName : ""}`,
                );
                isPendingDesktopUpload.current = true;
                pendingDesktopUploadConfirmationOptions.current = {
                    importTakeoutFavorites,
                    includePartnerSharedFiles,
                };
                pendingDesktopUploadCollectionName.current = collectionName;
                setDesktopFilePaths(filePaths);
                setDesktopZipItems(zipItems);
                setPreUploadSkippedFiles(preUploadSkippedFiles ?? []);
            });
        }
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    useEffect(() => {
        if (watchFolderView) {
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
            void desktopFilesAndZipItems(electron, files).then(
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
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [selectedInputFiles, dragAndDropFiles]);

    useEffect(() => {
        // ZIP paths are synthetic and used only for folder grouping.
        const allItemAndPaths = [
            webFiles.map((f) => [f, pathLikeForWebFile(f)]),
            desktopFiles.map((fp) => [fp, fp.path]),
            desktopFilePaths.map((p) => [p, p]),
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

        // Do not reuse a confirmation from an earlier selection.
        setUploadConfirmation(undefined);
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
                const confirmationOptions =
                    pendingDesktopUploadConfirmationOptions.current;
                pendingDesktopUploadConfirmationOptions.current = {};
                if (pendingDesktopUploadCollectionName.current) {
                    // Watch folders must match hidden albums instead of duplicating them.
                    void uploadFilesToNewCollections("root", {
                        collectionName:
                            pendingDesktopUploadCollectionName.current,
                        includeHiddenCollections: true,
                        skipConfirmation: true,
                        ...confirmationOptions,
                    });
                    pendingDesktopUploadCollectionName.current = undefined;
                } else {
                    void uploadFilesToNewCollections("parent", {
                        includeHiddenCollections: true,
                        skipConfirmation: true,
                        ...confirmationOptions,
                    });
                }
                return;
            }

            if (electron && _selectedUploadType == "zips") {
                void uploadFilesToNewCollections("parent");
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
                    void uploadFilesToExistingCollection(
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
                    void uploadFilesToExistingCollection(
                        collection,
                        prunedItemAndPaths,
                    ),
                onCreateCollection: showNextModal,
                onCancel: handleCollectionSelectorCancel,
            });
        })();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [webFiles, desktopFiles, desktopFilePaths, desktopZipItems]);

    const preCollectionCreationAction = () => {
        onCloseCollectionSelector?.();
        props.setShouldDisableDropzone(uploadManager.isUploadInProgress());
        setUploadPhase("preparing");
        uploadManager.showUploadProgressDialog();
    };

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

    const handleTakeoutFavoritesPostUpload = async (
        batchResult: UploadBatchResult,
        postUploadTargetCollection: Collection | undefined,
        importTakeoutFavorites: boolean,
    ) => {
        if (!importTakeoutFavorites) return;

        if (
            !batchResult.itemResults.some(
                ({ takeoutFavorited }) => takeoutFavorited,
            )
        ) {
            return;
        }

        const hiddenCollectionIDs = new Set(
            (await savedHiddenCollections()).map(({ id }) => id),
        );

        if (
            postUploadTargetCollection &&
            isHiddenCollection(postUploadTargetCollection)
        ) {
            // The temporary upload album is not the effective destination.
            hiddenCollectionIDs.add(postUploadTargetCollection.id);
        }

        if (props.isInHiddenSection) {
            // The pull may not include every newly created hidden album yet.
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
        if (uploadItemsAndPaths.current !== uploadItemAndPaths) return;

        const hint = importSourceHint(uploadItemAndPaths, isInternalUser);
        if (uploadItemAndPaths.length > 1 || hint != "generic")
            setUploadConfirmation({ phase: "counting", importSource: hint });

        try {
            const { count: fileCount, importSource } =
                await uploadableMediaCount([uploadItemAndPaths]);
            if (uploadItemsAndPaths.current !== uploadItemAndPaths) return;
            if (fileCount == 1 && importSource == "generic") {
                setUploadConfirmation(undefined);
                void commitUploadToExistingCollection(
                    collection,
                    uploadItemAndPaths,
                    true,
                );
                return;
            }
            setUploadConfirmation({
                phase: "ready",
                pendingUpload: {
                    type: "existing-collection",
                    collection,
                    uploadItemAndPaths,
                },
                fileCount,
                albumCount: 1,
                importSource,
                importFavorites: true,
                includePartnerSharedFiles: true,
            });
        } catch (e) {
            if (uploadItemsAndPaths.current !== uploadItemAndPaths) return;
            cancelPendingUpload();
            onGenericError(e);
        }
    };

    const commitUploadToExistingCollection = async (
        collection: Collection,
        uploadItemAndPaths: UploadItemAndPath[],
        importTakeoutFavorites: boolean,
        includePartnerSharedFiles = true,
    ) => {
        try {
            preCollectionCreationAction();
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
                    importTakeoutFavorites,
                    includePartnerSharedFiles,
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
        {
            collectionName,
            includeHiddenCollections,
            createHidden,
            skipConfirmation,
            importTakeoutFavorites,
            includePartnerSharedFiles,
        }: NewCollectionsOptions = {},
    ) => {
        const uploadItemAndPaths = uploadItemsAndPaths.current;
        const hint = importSourceHint(uploadItemAndPaths, isInternalUser);
        if (
            !skipConfirmation &&
            (uploadItemAndPaths.length > 1 || hint != "generic")
        )
            setUploadConfirmation({ phase: "counting", importSource: hint });

        let collectionNameToUploadItems = new Map<
            string,
            UploadItemAndPath[]
        >();
        if (mapping == "root") {
            collectionNameToUploadItems.set(
                // Un-enforced convention is that collectionName is always set
                // when mapping is "root". TODO: Reflect this in types.
                collectionName!,
                uploadItemAndPaths,
            );
        } else {
            try {
                collectionNameToUploadItems =
                    await groupItemsBasedOnParentFolder(
                        uploadItemAndPaths,
                        collectionName,
                    );
            } catch (e) {
                if (uploadItemsAndPaths.current !== uploadItemAndPaths) return;
                cancelPendingUpload();
                onGenericError(e);
                return;
            }
        }

        if (uploadItemsAndPaths.current !== uploadItemAndPaths) return;

        if (skipConfirmation) {
            void commitUploadToNewCollections(
                uploadItemAndPaths,
                collectionNameToUploadItems,
                { includeHiddenCollections, createHidden },
                importTakeoutFavorites ?? true,
                includePartnerSharedFiles ?? true,
            );
            return;
        }

        try {
            const { count: fileCount, importSource } =
                await uploadableMediaCount([
                    ...collectionNameToUploadItems.values(),
                ]);
            if (uploadItemsAndPaths.current !== uploadItemAndPaths) return;
            if (fileCount == 1 && importSource == "generic") {
                setUploadConfirmation(undefined);
                void commitUploadToNewCollections(
                    uploadItemAndPaths,
                    collectionNameToUploadItems,
                    { includeHiddenCollections, createHidden },
                    importTakeoutFavorites ?? true,
                    includePartnerSharedFiles ?? true,
                );
                return;
            }
            setUploadConfirmation({
                phase: "ready",
                pendingUpload: {
                    type: "new-collections",
                    uploadItemAndPaths,
                    collectionNameToUploadItems,
                    includeHiddenCollections,
                    createHidden,
                },
                fileCount,
                albumCount: collectionNameToUploadItems.size,
                importSource,
                importFavorites: importTakeoutFavorites ?? true,
                includePartnerSharedFiles: includePartnerSharedFiles ?? true,
            });
        } catch (e) {
            if (uploadItemsAndPaths.current !== uploadItemAndPaths) return;
            cancelPendingUpload();
            onGenericError(e);
        }
    };

    const commitUploadToNewCollections = async (
        uploadItemAndPaths: UploadItemAndPath[],
        collectionNameToUploadItems: Map<string, UploadItemAndPath[]>,
        { includeHiddenCollections, createHidden }: NewCollectionsOptions,
        importTakeoutFavorites: boolean,
        includePartnerSharedFiles = true,
    ) => {
        preCollectionCreationAction();
        let uploadItemsWithCollection: UploadItemWithCollection[] = [];
        const collections: Collection[] = [];
        try {
            await onRemoteFilesPull();
            // Hidden uploads search hidden albums only. Watch folders search all.
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
                importTakeoutFavorites,
                includePartnerSharedFiles,
            },
        );
        if (uploadItemsAndPaths.current === uploadItemAndPaths) {
            uploadItemsAndPaths.current = [];
        }
    };

    const handleUploadConfirm = () => {
        const confirmation = uploadConfirmation;
        if (confirmation?.phase != "ready") return;

        setUploadConfirmation(undefined);
        const { pendingUpload, importFavorites, includePartnerSharedFiles } =
            confirmation;
        if (pendingUpload.type == "existing-collection") {
            void commitUploadToExistingCollection(
                pendingUpload.collection,
                pendingUpload.uploadItemAndPaths,
                importFavorites,
                includePartnerSharedFiles,
            );
        } else {
            void commitUploadToNewCollections(
                pendingUpload.uploadItemAndPaths,
                pendingUpload.collectionNameToUploadItems,
                {
                    includeHiddenCollections:
                        pendingUpload.includeHiddenCollections,
                    createHidden: pendingUpload.createHidden,
                },
                importFavorites,
                includePartnerSharedFiles,
            );
        }
    };

    const cancelPendingUpload = () => {
        setUploadConfirmation(undefined);
        uploadItemsAndPaths.current = [];
        onCloseCollectionSelector?.();
        resetUploadUIState();
    };

    const handleImportFavoritesChange = (
        _event: React.ChangeEvent<HTMLInputElement>,
        checked: boolean,
    ) =>
        setUploadConfirmation((c) =>
            c?.phase == "ready" ? { ...c, importFavorites: checked } : c,
        );

    const handleIncludePartnerSharedFilesChange = (
        _event: React.ChangeEvent<HTMLInputElement>,
        checked: boolean,
    ) =>
        setUploadConfirmation((c) =>
            c?.phase == "ready"
                ? { ...c, includePartnerSharedFiles: checked }
                : c,
        );

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
        const isFolderWatchUpload = isDesktop && watcher.isUploadRunning();
        const handleResult = async (result: UploadBatchResult) => {
            await handlePostUploadBatchResult(
                result,
                opts?.postUploadTargetCollection,
            );
            await handleTakeoutFavoritesPostUpload(
                result,
                opts?.postUploadTargetCollection,
                opts?.importTakeoutFavorites ?? true,
            );
        };
        try {
            retrySharedAlbumUploadTarget.current =
                opts?.postUploadTargetCollection;
            retryImportTakeoutFavorites.current =
                opts?.importTakeoutFavorites ?? true;
            retryIncludePartnerSharedFiles.current =
                opts?.includePartnerSharedFiles ?? true;
            await preUploadAction();
            if (
                opts?.persistPendingUploads &&
                electron &&
                !isPendingDesktopUpload.current &&
                !watcher.isUploadRunning()
            ) {
                await setPendingUploads(
                    electron,
                    collections,
                    uploadItemsWithCollection
                        .map(({ uploadItem }) => uploadItem)
                        .filter((x) => x !== undefined),
                    preUploadSkippedFiles,
                    opts.importTakeoutFavorites ?? true,
                    opts.includePartnerSharedFiles ?? true,
                );
            }
            const batchResult = await uploadManager.uploadItems(
                uploadItemsWithCollection,
                collections,
                {
                    skipDuplicateAddToUploadCollection:
                        !!opts?.postUploadTargetCollection,
                    includePartnerSharedFiles: opts?.includePartnerSharedFiles,
                    onChunkResult: isFolderWatchUpload
                        ? handleResult
                        : undefined,
                },
            );
            if (!batchResult.processedAny) closeUploadProgress();
            if (!isFolderWatchUpload || batchResult.itemResults.length)
                await handleResult(batchResult);
            if (isDesktop) {
                if (isFolderWatchUpload) {
                    await watcher.allFileUploadsDone(uploadItemsWithCollection);
                } else if (watcher.isSyncPaused()) {
                    // Resume the watch upload displaced by this user upload.
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
                    includePartnerSharedFiles:
                        retryIncludePartnerSharedFiles.current,
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
                retryImportTakeoutFavorites.current,
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
                    onClick: () =>
                        void redirectToCustomerPortal().catch(onGenericError),
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
        didSubmitNewAlbumName.current = true;
        void uploadFilesToNewCollections("root", {
            collectionName,
            createHidden: props.isInHiddenSection,
        });
    };

    const handleNewAlbumNameInputClose = () => {
        newAlbumNameInputVisibilityProps.onClose();
        if (!didSubmitNewAlbumName.current) {
            onCloseCollectionSelector?.();
            handleCollectionSelectorCancel();
        }
        didSubmitNewAlbumName.current = false;
    };

    const cancelUploads = () => {
        uploadManager.cancelRunningUpload();
    };

    const handleUploadTypeSelect = (type: UploadType) => {
        selectedUploadType.current = type;
        // Native pickers blur the window; this trusted flow must not lock it.
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
        uploadFilesToNewCollections(mapping, {
            collectionName:
                importSuggestion.rootFolderName ||
                t("autogenerated_default_album_name"),
            createHidden: props.isInHiddenSection,
        });

    const readyConfirmation =
        uploadConfirmation?.phase == "ready" ? uploadConfirmation : undefined;

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
                isInternalUser={isInternalUser}
                pendingUploadType={
                    isInputPending ? selectedUploadType.current : undefined
                }
                onSelect={handleUploadTypeSelect}
            />
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
            <CanvasReadbackBlockedDialog
                open={showCanvasReadbackBlockedDialog}
                onClose={() => setShowCanvasReadbackBlockedDialog(false)}
            />
            <UploadConfirmationDialog
                open={!!uploadConfirmation}
                loading={uploadConfirmation?.phase == "counting"}
                importSource={uploadConfirmation?.importSource ?? "generic"}
                fileCount={readyConfirmation?.fileCount ?? 0}
                albumCount={readyConfirmation?.albumCount ?? 0}
                importFavorites={readyConfirmation?.importFavorites ?? true}
                onImportFavoritesChange={handleImportFavoritesChange}
                includePartnerSharedFiles={
                    readyConfirmation?.includePartnerSharedFiles ?? true
                }
                onIncludePartnerSharedFilesChange={
                    handleIncludePartnerSharedFilesChange
                }
                onConfirm={handleUploadConfirm}
                onCancel={cancelPendingUpload}
            />
            <SingleInputDialog
                {...newAlbumNameInputVisibilityProps}
                variant="v2"
                onClose={handleNewAlbumNameInputClose}
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
                // Malformed ZIPs return as data; this catch means IPC failed.
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

const pathLikeForWebFile = (file: File): string =>
    firstNonEmpty([
        "path" in file && typeof file.path == "string" ? file.path : undefined,
        file.webkitRelativePath,
        file.name,
    ])!;

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

    // All paths here use POSIX separators.
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
        // Hidden uploads must not match a visible album with the same name.
        if (createHidden && !isHiddenCollection(collection)) continue;

        if (
            collection.name == albumName &&
            (collection.type == "album" ||
                collection.type == "folder" ||
                collection.type == "uncategorized") &&
            collection.magicMetadata?.data.subType !=
                CollectionSubType.quicklink &&
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
    importTakeoutFavorites: boolean,
    includePartnerSharedFiles: boolean,
) => {
    let collectionName: string | undefined;
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
        importTakeoutFavorites,
        includePartnerSharedFiles,
    });
};

type UploadTypeSelectorProps = ModalVisibilityProps & {
    intent: UploadTypeSelectorIntent;
    isInternalUser: boolean;
    pendingUploadType: UploadType | undefined;
    onSelect: (type: UploadType) => void;
};

const UploadTypeSelector: React.FC<UploadTypeSelectorProps> = ({
    open,
    onClose,
    intent,
    isInternalUser,
    pendingUploadType,
    onSelect,
}) => {
    const isSheet = useIsUploadSheet();

    const handleClose: DialogProps["onClose"] = () => {
        // The browser may still be processing the selection after the picker closes.
        if (pendingUploadType) return;
        onClose();
    };

    return (
        <Dialog
            open={open}
            onClose={handleClose}
            fullWidth
            slots={isSheet ? { transition: SlideUpTransition } : undefined}
            slotProps={{
                paper: {
                    sx: [
                        (theme) => ({
                            maxWidth: "375px",
                            p: 1,
                            borderRadius: "28px",
                            boxShadow: "none",
                            border: "1px solid",
                            borderColor: "stroke.faint",
                            "&:has([data-default-options], [data-takeout-options])":
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
                        uploadSheetPaperSx,
                        {
                            [uploadSheetMediaQuery]: {
                                "&&": {
                                    maxWidth: "none",
                                    borderRadius: "20px 20px 0 0",
                                },
                            },
                        },
                    ],
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
                    intent,
                    isInternalUser,
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
    "onClose" | "intent" | "isInternalUser" | "pendingUploadType" | "onSelect"
>;

const UploadOptions: React.FC<UploadOptionsProps> = ({
    intent,
    isInternalUser,
    pendingUploadType,
    onSelect,
    onClose,
}) => {
    // Keep dialog state in this child so it resets when the dialog closes.
    const [provider, setProvider] = useState<"google" | "apple">();
    const selectedProvider =
        provider == "apple" && !isInternalUser ? undefined : provider;

    return selectedProvider ? (
        <TakeoutOptions
            provider={selectedProvider}
            isFolderSelectionPending={pendingUploadType == "folders"}
            onBack={() => setProvider(undefined)}
            onSelectFolder={() => onSelect("folders")}
            onSelectZips={() => onSelect("zips")}
            {...{ onClose }}
        />
    ) : (
        <DefaultOptions
            intent={intent}
            isFileSelectionPending={pendingUploadType == "files"}
            isFolderSelectionPending={pendingUploadType == "folders"}
            onSelectFiles={() => onSelect("files")}
            onSelectFolder={() => onSelect("folders")}
            onSelectGooglePhotos={() => setProvider("google")}
            {...(isInternalUser && {
                onSelectApplePhotos: () => setProvider("apple"),
            })}
            {...{ onClose }}
        />
    );
};
