// TODO: Too many null assertions in this file. The types need reworking.
import { useAlbumsAppContext } from "@/app/context/albums-app-context";
import {
    savedPublicCollectionUploaderName,
    savePublicCollectionUploaderName,
} from "@/public-album/data/storage/public-albums-fdb";
import { UploaderNameInput } from "@/public-album/upload/components/UploaderNameInput";
import {
    uploadPathPrefix,
    type UploadPhase,
} from "@/public-album/upload/pipeline";
import type { ParsedMetadataJSON } from "@/public-album/upload/pipeline/metadata-json";
import {
    sessionExpiredErrorMessage,
    storageLimitExceededErrorMessage,
    subscriptionExpiredErrorMessage,
} from "@/public-album/upload/pipeline/upload-service";
import type {
    InProgressUpload,
    SegregatedFinishedUploads,
    UploadCounter,
    UploadFileNames,
    UploadItemWithCollection,
} from "@/public-album/upload/services/upload-manager";
import { uploadManager } from "@/public-album/upload/services/upload-manager";
import { Dialog, type DialogProps } from "@mui/material";
import { useIsTouchscreen } from "ente-base/components/utils/hooks";
import {
    useModalVisibility,
    type ModalVisibilityProps,
} from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import { basename } from "ente-base/file-name";
import type { PublicAlbumsCredentials } from "ente-base/http";
import log from "ente-base/log";
import {
    uploadSheetPaperSx,
    useIsUploadSheet,
} from "ente-gallery/components/upload-progress/bottom-sheet";
import { UploadProgress } from "ente-gallery/components/upload-progress/UploadProgress";
import { CanvasReadbackBlockedDialog } from "ente-gallery/components/upload/CanvasReadbackBlockedDialog";
import { DefaultOptions } from "ente-gallery/components/upload/DefaultOptions";
import { useFileInput } from "ente-gallery/components/utils/use-file-input";
import { hasReliableCanvasReadback } from "ente-gallery/utils/upload/canvas-integrity";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { SlideUpTransition } from "ente-new/photos/components/mui/SlideUpTransition";
import { firstNonEmpty } from "ente-utils/array";
import { t } from "i18next";
import React, { useCallback, useEffect, useRef, useState } from "react";

interface RemotePullOpts {
    silent?: boolean;
}

export interface UploadProps {
    publicAlbumsCredentials?: PublicAlbumsCredentials;
    uploadTypeSelectorView: boolean;
    dragAndDropFiles: File[];
    uploadCollection?: Collection;
    closeUploadTypeSelector: () => void;
    setLoading: (loading: boolean) => void;
    setShouldDisableDropzone: (value: boolean) => void;
    onRemotePull: (opts?: RemotePullOpts) => Promise<void>;
    onUploadFile: (file: EnteFile) => void;
    onShowSessionExpiredDialog: () => void;
    onUploadInProgressChange?: (value: boolean) => void;
}

type UploadType = "files" | "folders";
type WebUploadItemAndPath = [File, string];

export const Upload: React.FC<UploadProps> = ({
    publicAlbumsCredentials,
    dragAndDropFiles,
    uploadCollection,
    onRemotePull,
    onUploadFile,
    onShowSessionExpiredDialog,
    onUploadInProgressChange,
    ...props
}) => {
    const { onGenericError } = useBaseContext();
    const { showNotification } = useAlbumsAppContext();

    const [uploadProgressView, setUploadProgressView] = useState(false);
    const [
        showCanvasReadbackBlockedDialog,
        setShowCanvasReadbackBlockedDialog,
    ] = useState(false);
    const [uploadPhase, setUploadPhase] = useState<UploadPhase>("preparing");
    const [uploadFileNames, setUploadFileNames] = useState<UploadFileNames>(
        new Map(),
    );
    const [uploadCounter, setUploadCounter] = useState<UploadCounter>({
        finished: 0,
        total: 0,
    });
    const [inProgressUploads, setInProgressUploads] = useState<
        InProgressUpload[]
    >([]);
    const [finishedUploads, setFinishedUploads] =
        useState<SegregatedFinishedUploads>(new Map());
    const [percentComplete, setPercentComplete] = useState(0);
    const [hasLivePhotos, setHasLivePhotos] = useState(false);
    const [uploaderName, setUploaderName] = useState("");
    const [pendingUploadFileCount, setPendingUploadFileCount] = useState(0);
    const {
        show: showUploaderNameInput,
        props: uploaderNameInputVisibilityProps,
    } = useModalVisibility();

    const [webFiles, setWebFiles] = useState<File[]>([]);
    const uploadItemsAndPaths = useRef<WebUploadItemAndPath[]>([]);
    const selectedUploadType = useRef<UploadType | undefined>(undefined);
    const currentUploadPromise = useRef<Promise<void> | undefined>(undefined);

    const [isInputPending, setIsInputPending] = useState(false);
    const [selectedInputFiles, setSelectedInputFiles] = useState<File[]>([]);

    const reportUploadInProgress = useCallback(
        (value: boolean = uploadManager.isUploadInProgress()) =>
            onUploadInProgressChange?.(value),
        [onUploadInProgressChange],
    );

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

    const closeUploadProgress = () => setUploadProgressView(false);

    const handleUploaderNameInputClose = () => {
        uploaderNameInputVisibilityProps.onClose();
        uploadItemsAndPaths.current = [];
    };

    useEffect(() => {
        uploadManager.init(
            {
                setPercentComplete,
                setUploadCounter,
                setInProgressUploads,
                setFinishedUploads,
                setUploadPhase,
                setUploadFilenames: setUploadFileNames,
                setHasLivePhotos,
            },
            onUploadFile,
            publicAlbumsCredentials,
        );

        if (uploadManager.isUploadRunning()) {
            setUploadProgressView(true);
        }
        reportUploadInProgress();
    }, [onUploadFile, publicAlbumsCredentials, reportUploadInProgress]);

    useEffect(
        () => () => {
            onUploadInProgressChange?.(false);
        },
        [onUploadInProgressChange],
    );

    useEffect(() => {
        let files: File[];

        switch (selectedUploadType.current) {
            case "files":
            case "folders":
                files = selectedInputFiles;
                break;

            default:
                files = dragAndDropFiles;
                break;
        }

        setWebFiles(files);
    }, [selectedInputFiles, dragAndDropFiles]);

    useEffect(() => {
        const allItemAndPaths = webFiles.map(
            (file) => [file, pathLikeForWebFile(file)] as WebUploadItemAndPath,
        );

        if (allItemAndPaths.length == 0) return;

        if (uploadManager.isUploadRunning()) {
            log.info(
                "Ignoring new public album upload request when upload is already running",
            );
            selectedUploadType.current = undefined;
            return;
        }

        if (!hasReliableCanvasReadback()) {
            log.warn("Canvas readback integrity check failed; blocking upload");
            setWebFiles([]);
            selectedUploadType.current = undefined;
            setShowCanvasReadbackBlockedDialog(true);
            return;
        }

        props.closeUploadTypeSelector();
        props.setLoading(true);
        setWebFiles([]);

        const prunedItemAndPaths = allItemAndPaths.filter(
            ([, path]) => !basename(path).startsWith("."),
        );
        uploadItemsAndPaths.current = prunedItemAndPaths;
        setPendingUploadFileCount(prunedItemAndPaths.length);
        selectedUploadType.current = undefined;
        props.setLoading(false);

        if (uploadItemsAndPaths.current.length == 0) return;

        if (!publicAlbumsCredentials) {
            uploadItemsAndPaths.current = [];
            onGenericError(new Error("Missing public album credentials"));
            return;
        }

        if (!uploadCollection) {
            uploadItemsAndPaths.current = [];
            onGenericError(new Error("Missing public album collection"));
            return;
        }

        void (async () => {
            try {
                setUploaderName(
                    (await savedPublicCollectionUploaderName(
                        publicAlbumsCredentials.accessToken,
                    )) ?? "",
                );
                showUploaderNameInput();
            } catch (e) {
                uploadItemsAndPaths.current = [];
                onGenericError(e);
            }
        })();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [publicAlbumsCredentials, uploadCollection, webFiles]);

    const uploadFilesToExistingCollection = async (
        collection: Collection,
        uploaderName?: string,
    ) => {
        const uploadItemsWithCollection: UploadItemWithCollection[] =
            uploadItemsAndPaths.current.map(([uploadItem, path], index) => ({
                uploadItem,
                pathPrefix: uploadPathPrefix(path),
                localID: index,
                collectionID: collection.id,
            }));
        await waitInQueueAndUploadFiles(
            uploadItemsWithCollection,
            [collection],
            uploaderName,
        );
        uploadItemsAndPaths.current = [];
    };

    const waitInQueueAndUploadFiles = async (
        uploadItemsWithCollection: UploadItemWithCollection[],
        collections: Collection[],
        uploaderName?: string,
    ) => {
        const currentPromise = currentUploadPromise.current;
        currentUploadPromise.current = (async () => {
            if (currentPromise) await currentPromise;
            return uploadFiles(
                uploadItemsWithCollection,
                collections,
                uploaderName,
            );
        })();
        await currentUploadPromise.current;
    };

    const preUploadAction = async (
        parsedMetadataJSONMap?: Map<string, ParsedMetadataJSON>,
    ) => {
        props.setShouldDisableDropzone(true);
        setUploadPhase("preparing");
        uploadManager.prepareForNewUpload(parsedMetadataJSONMap);
        setUploadProgressView(true);
        await onRemotePull({ silent: true });
    };

    const postUploadAction = () => {
        props.setShouldDisableDropzone(false);
        void onRemotePull();
    };

    const uploadFiles = async (
        uploadItemsWithCollection: UploadItemWithCollection[],
        collections: Collection[],
        uploaderName?: string,
    ) => {
        reportUploadInProgress(true);
        try {
            await preUploadAction();
            const wereFilesProcessed = await uploadManager.uploadItems(
                uploadItemsWithCollection,
                collections,
                uploaderName,
            );
            if (!wereFilesProcessed) closeUploadProgress();
        } catch (e) {
            log.error("Failed to upload files", e);
            closeUploadProgress();
            notifyUser(e);
        } finally {
            reportUploadInProgress(false);
            postUploadAction();
        }
    };

    const retryFailed = async () => {
        reportUploadInProgress(true);
        try {
            log.info("Retrying failed uploads");
            const { items, collections, parsedMetadataJSONMap } =
                uploadManager.failedItemState();
            const uploaderName = uploadManager.getUploaderName();
            await preUploadAction(parsedMetadataJSONMap);
            await uploadManager.uploadItems(items, collections, uploaderName);
        } catch (e) {
            log.error("Retrying failed uploads failed", e);
            closeUploadProgress();
            notifyUser(e);
        } finally {
            reportUploadInProgress(false);
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
                    title: t("generic_error_retry"),
                    caption: t("subscription_expired"),
                });
                break;
            case storageLimitExceededErrorMessage:
                showNotification({
                    color: "critical",
                    title: t("generic_error_retry"),
                    caption: t("storage_quota_exceeded"),
                });
                break;
            default:
                showNotification({
                    color: "critical",
                    title: t("generic_error_retry"),
                });
        }
    };

    const cancelUploads = () => {
        uploadManager.cancelRunningUpload();
    };

    const handleUploadTypeSelect = (type: UploadType) => {
        selectedUploadType.current = type;
        setIsInputPending(true);

        switch (type) {
            case "files":
                openFileSelector();
                break;
            case "folders":
                openFolderSelector();
                break;
        }
    };

    const handlePublicUpload = (name: string) => {
        if (!publicAlbumsCredentials) {
            throw new Error("Missing public album credentials");
        }

        if (!uploadCollection) {
            throw new Error("Missing public album collection");
        }

        void savePublicCollectionUploaderName(
            publicAlbumsCredentials.accessToken,
            name,
        );
        void uploadFilesToExistingCollection(uploadCollection, name);
    };

    return (
        <>
            <Inputs
                {...{ getFileSelectorInputProps, getFolderSelectorInputProps }}
            />
            {props.uploadTypeSelectorView ? (
                <UploadTypeSelector
                    open
                    onClose={props.closeUploadTypeSelector}
                    publicAlbumsCredentials={publicAlbumsCredentials}
                    pendingUploadType={
                        isInputPending ? selectedUploadType.current : undefined
                    }
                    onSelect={handleUploadTypeSelect}
                />
            ) : null}
            <UploadProgress
                open={uploadProgressView}
                onClose={closeUploadProgress}
                percentComplete={percentComplete}
                uploadFileNames={uploadFileNames}
                uploadCounter={uploadCounter}
                uploadPhase={uploadPhase}
                inProgressUploads={inProgressUploads}
                hasLivePhotos={hasLivePhotos}
                retryFailed={retryFailed}
                finishedUploads={finishedUploads}
                cancelUploads={cancelUploads}
            />
            <CanvasReadbackBlockedDialog
                open={showCanvasReadbackBlockedDialog}
                onClose={() => setShowCanvasReadbackBlockedDialog(false)}
            />
            <UploaderNameInput
                open={uploaderNameInputVisibilityProps.open}
                onClose={handleUploaderNameInputClose}
                uploaderName={uploaderName}
                uploadFileCount={pendingUploadFileCount}
                onSubmit={handlePublicUpload}
            />
        </>
    );
};

type GetInputProps = () => React.HTMLAttributes<HTMLInputElement>;

interface InputsProps {
    getFileSelectorInputProps: GetInputProps;
    getFolderSelectorInputProps: GetInputProps;
}

const Inputs: React.FC<InputsProps> = ({
    getFileSelectorInputProps,
    getFolderSelectorInputProps,
}) => (
    <>
        <input {...getFileSelectorInputProps()} />
        <input {...getFolderSelectorInputProps()} />
    </>
);

const pathLikeForWebFile = (file: File): string =>
    firstNonEmpty([
        "path" in file && typeof file.path == "string" ? file.path : undefined,
        file.webkitRelativePath,
        file.name,
    ])!;

type UploadTypeSelectorProps = ModalVisibilityProps & {
    pendingUploadType: UploadType | undefined;
    onSelect: (type: UploadType) => void;
} & Pick<UploadProps, "publicAlbumsCredentials">;

const UploadTypeSelector: React.FC<UploadTypeSelectorProps> = ({
    open,
    onClose,
    publicAlbumsCredentials,
    pendingUploadType,
    onSelect,
}) => {
    const directlyShowUploadFiles = useIsTouchscreen();

    useEffect(() => {
        if (open && directlyShowUploadFiles && publicAlbumsCredentials) {
            onSelect("files");
            onClose();
        }
    }, [
        directlyShowUploadFiles,
        onClose,
        onSelect,
        open,
        publicAlbumsCredentials,
    ]);

    const handleClose: DialogProps["onClose"] = () => {
        if (pendingUploadType) return;
        onClose();
    };

    const isSheet = useIsUploadSheet();

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
                            maxWidth: "440px",
                            p: 0,
                            borderRadius: "20px",
                            boxShadow: "none",
                            border: "1px solid",
                            borderColor: "stroke.faint",
                            backgroundColor: "secondary.main",
                            ...theme.applyStyles("dark", {
                                backgroundColor: "background.paper",
                            }),
                        }),
                        uploadSheetPaperSx,
                    ],
                },
            }}
            sx={{
                "& .MuiBackdrop-root": {
                    backgroundColor: "rgba(0, 0, 0, 0.5)",
                },
            }}
        >
            <DefaultOptions
                intent="collect"
                isFileSelectionPending={pendingUploadType == "files"}
                isFolderSelectionPending={pendingUploadType == "folders"}
                onSelectFiles={() => onSelect("files")}
                onSelectFolder={() => onSelect("folders")}
                onClose={onClose}
            />
        </Dialog>
    );
};
