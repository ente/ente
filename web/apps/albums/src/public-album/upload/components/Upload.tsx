// TODO: Audit this file
// TODO: Too many null assertions in this file. The types need reworking.
/* eslint-disable react-hooks/exhaustive-deps */
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
import { Album02Icon, Folder01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import {
    Box,
    CircularProgress,
    Dialog,
    DialogTitle,
    styled,
    Typography,
    type DialogProps,
} from "@mui/material";
import { SpacedRow } from "ente-base/components/containers";
import { DialogCloseIconButton } from "ente-base/components/mui/DialogCloseIconButton";
import { RowButton } from "ente-base/components/RowButton";
import { useIsTouchscreen } from "ente-base/components/utils/hooks";
import {
    useModalVisibility,
    type ModalVisibilityProps,
} from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import { basename } from "ente-base/file-name";
import type { PublicAlbumsCredentials } from "ente-base/http";
import log from "ente-base/log";
import { CanvasReadbackBlockedDialog } from "ente-gallery/components/upload/CanvasReadbackBlockedDialog";
import { UploadProgress } from "ente-gallery/components/UploadProgress";
import { useFileInput } from "ente-gallery/components/utils/use-file-input";
import { hasReliableCanvasReadback } from "ente-gallery/utils/upload/canvas-integrity";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { firstNonEmpty } from "ente-utils/array";
import { t } from "i18next";
import React, { useCallback, useEffect, useRef, useState } from "react";

interface RemotePullOpts {
    /**
     * Perform the pull without showing a global loading bar.
     *
     * Default: `false`.
     */
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

/**
 * Public album uploader.
 *
 * This is a trimmed copy of the photos app uploader that only keeps the web
 * flow needed by the public albums app: select or drop files/folders, ask for
 * the uploader's name, and upload into the current public collection.
 */
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

    /**
     * `true` if we've activated one hidden input and are waiting for the
     * browser to hand the file selection back to us.
     */
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
                // eslint-disable-next-line @typescript-eslint/ban-ts-comment
                // @ts-ignore
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
            <UploadTypeSelector
                open={props.uploadTypeSelectorView}
                onClose={props.closeUploadTypeSelector}
                publicAlbumsCredentials={publicAlbumsCredentials}
                pendingUploadType={
                    isInputPending ? selectedUploadType.current : undefined
                }
                onSelect={handleUploadTypeSelect}
            />
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
 * 3. If the user drags-and-drops, then react-dropzone internally converts
 *    `webkitRelativePath` to `path`, but otherwise behaves the same as case 2.
 */
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
            <UploadOptions {...{ pendingUploadType, onSelect, onClose }} />
        </Dialog>
    );
};

type UploadOptionsProps = Pick<
    UploadTypeSelectorProps,
    "onClose" | "pendingUploadType" | "onSelect"
>;

const UploadOptions: React.FC<UploadOptionsProps> = ({
    pendingUploadType,
    onSelect,
    onClose,
}) => (
    <>
        <SpacedRow>
            <DialogTitle variant="h5">{t("select_photos")}</DialogTitle>
            <DialogCloseIconButton {...{ onClose }} />
        </SpacedRow>
        <Box sx={{ p: "12px", pt: "16px" }}>
            <RoundedButtonStack>
                <RowButton
                    startIcon={<HugeiconsIcon icon={Album02Icon} size={20} />}
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
                <RowButton
                    startIcon={<HugeiconsIcon icon={Folder01Icon} size={20} />}
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

const PendingIndicator = () => (
    <CircularProgress size={18} sx={{ color: "stroke.muted" }} />
);

const RoundedButtonStack = styled("div")`
    display: flex;
    flex-direction: column;
    gap: 4px;
    & > button {
        border-radius: 16px;
    }
`;
