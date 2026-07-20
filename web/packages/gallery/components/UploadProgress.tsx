// TODO: Audit this file
/* eslint-disable @typescript-eslint/no-unsafe-argument */
import { DragDropVerticalIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import CloseIcon from "@mui/icons-material/Close";
import ExpandMoreIcon from "@mui/icons-material/ExpandMore";
import UnfoldLessIcon from "@mui/icons-material/UnfoldLess";
import UnfoldMoreIcon from "@mui/icons-material/UnfoldMore";
import {
    Accordion,
    AccordionDetails,
    AccordionSummary,
    Box,
    Button,
    Dialog,
    DialogActions,
    DialogContent,
    DialogTitle,
    Divider,
    LinearProgress,
    Paper,
    Snackbar,
    Stack,
    styled,
    Tooltip,
    Typography,
    type AccordionProps,
    type DialogProps,
} from "@mui/material";
import { SpacedRow } from "ente-base/components/containers";
import { FilledIconButton } from "ente-base/components/mui";
import { useBaseContext } from "ente-base/context";
import { basename } from "ente-base/file-name";
import { formattedListJoin } from "ente-base/i18n";
import type { PreUploadSkippedFile } from "ente-base/types/ipc";
import { t } from "i18next";
import memoize from "memoize-one";
import React, {
    createContext,
    useCallback,
    useContext,
    useEffect,
    useRef,
    useState,
    type ReactElement,
} from "react";
import { Trans } from "react-i18next";
import {
    areEqual,
    FixedSizeList as List,
    type ListChildComponentProps,
    type ListItemKeySelector,
} from "react-window";

interface UploadProgressProps {
    open: boolean;
    onClose: () => void;
    uploadCounter: UploadCounter;
    uploadPhase: UploadPhase;
    percentComplete: number;
    retryFailed: () => void;
    inProgressUploads: InProgressUpload[];
    uploadFileNames: UploadFileNames;
    finishedUploads: SegregatedFinishedUploads;
    preUploadSkippedFiles?: PreUploadSkippedFile[];
    hasLivePhotos: boolean;
    cancelUploads: () => void;
}

type FileID = number;

type PercentageUploaded = number;

type UploadPhase =
    | "preparing"
    | "readingMetadata"
    | "uploading"
    | "cancelling"
    | "done";

interface UploadCounter {
    finished: number;
    total: number;
}

interface InProgressUpload {
    localFileID: FileID;
    progress: PercentageUploaded;
}

type FinishedUploadType =
    | "unsupported"
    | "zeroSize"
    | "tooLarge"
    | "partnerShared"
    | "largerThanAvailableStorage"
    | "blocked"
    | "failed"
    | "alreadyUploaded"
    | "uploadedWithStaticThumbnail"
    | "uploaded";

type SegregatedFinishedUploads = Map<FinishedUploadType, FileID[]>;

type UploadFileNames = Map<FileID, string>;

export const UploadProgress: React.FC<UploadProgressProps> = ({
    open,
    onClose,
    uploadCounter,
    uploadPhase,
    percentComplete,
    retryFailed,
    uploadFileNames,
    hasLivePhotos,
    inProgressUploads,
    finishedUploads,
    preUploadSkippedFiles = [],
    cancelUploads,
}) => {
    const { showMiniDialog } = useBaseContext();

    const [expanded, setExpanded] = useState(false);
    const [dragPosition, setDragPosition] = useState<DragPosition>();

    useEffect(() => {
        if (open) {
            setExpanded(false);
            setDragPosition(undefined);
        }
    }, [open]);

    const handleClose = useCallback(() => {
        if (uploadPhase == "done") {
            onClose();
        } else {
            showMiniDialog({
                title: t("stop_uploads_title"),
                message: t("stop_uploads_message"),
                continue: {
                    text: t("yes_stop_uploads"),
                    color: "critical",
                    action: cancelUploads,
                },
                cancel: t("no"),
            });
        }
    }, [uploadPhase, onClose, cancelUploads, showMiniDialog]);

    if (!open) {
        return <></>;
    }

    return (
        <UploadProgressContext.Provider
            value={{
                open,
                onClose: handleClose,
                uploadCounter,
                uploadPhase,
                percentComplete,
                retryFailed,
                inProgressUploads,
                uploadFileNames,
                finishedUploads,
                preUploadSkippedFiles,
                hasLivePhotos,
                expanded,
                setExpanded,
                dragPosition,
                setDragPosition,
            }}
        >
            {expanded ? <UploadProgressDialog /> : <MinimizedUploadProgress />}
        </UploadProgressContext.Provider>
    );
};

/**
 * A context internal to the components of this file.
 */
interface UploadProgressContextT {
    open: boolean;
    onClose: () => void;
    uploadCounter: UploadCounter;
    uploadPhase: UploadPhase;
    percentComplete: number;
    retryFailed: () => void;
    inProgressUploads: InProgressUpload[];
    uploadFileNames: UploadFileNames;
    finishedUploads: SegregatedFinishedUploads;
    preUploadSkippedFiles: PreUploadSkippedFile[];
    hasLivePhotos: boolean;
    expanded: boolean;
    setExpanded: React.Dispatch<React.SetStateAction<boolean>>;
    dragPosition: DragPosition | undefined;
    setDragPosition: React.Dispatch<
        React.SetStateAction<DragPosition | undefined>
    >;
}

const UploadProgressContext = createContext<UploadProgressContextT | undefined>(
    undefined,
);

/**
 * Convenience hook to obtain the non-null asserted
 * {@link UploadProgressContext}.
 *
 * The non-null assertion is reasonable since we provide it to the tree always
 * in an invariant that is local to this file (and thus has less chance of being
 * invalid in the future).
 */
const useUploadProgressContext = () => useContext(UploadProgressContext)!;

interface DragPosition {
    x: number;
    y: number;
}

interface DragState {
    pointerStartX: number;
    pointerStartY: number;
    positionStartX: number;
    positionStartY: number;
    currentX: number;
    currentY: number;
    surface: HTMLElement;
    surfaceWidth: number;
    surfaceHeight: number;
}

const MinimizedUploadProgress: React.FC = () => {
    const { dragPosition, dragSurfaceProps } = useUploadProgressDrag();

    return (
        <Snackbar
            open
            anchorOrigin={{ horizontal: "right", vertical: "bottom" }}
        >
            <Paper
                {...dragSurfaceProps}
                sx={[
                    uploadProgressSurfaceSx,
                    { width: "min(360px, 100svw)" },
                    surfacePaperPositionSx(dragPosition),
                ]}
            >
                <UploadProgressHeader />
            </Paper>
        </Snackbar>
    );
};

const UploadProgressHeader: React.FC = () => (
    <>
        <UploadProgressTitle />
        <UploadProgressBar />
    </>
);

const UploadProgressTitle: React.FC = () => {
    const { setExpanded, onClose, expanded } = useUploadProgressContext();
    const toggleExpanded = () => setExpanded((expanded) => !expanded);

    return (
        <DialogTitle sx={{ pl: 1 }}>
            <SpacedRow>
                <Stack direction="row" sx={{ gap: 2, alignItems: "center" }}>
                    {!expanded && <UploadProgressDragIcon />}
                    <Box>
                        <Typography variant="h3">{t("file_upload")}</Typography>
                        <UploadProgressSubtitleText />
                    </Box>
                </Stack>
                <Stack direction="row" sx={{ gap: 1 }}>
                    <FilledIconButton onClick={toggleExpanded}>
                        {expanded ? <UnfoldLessIcon /> : <UnfoldMoreIcon />}
                    </FilledIconButton>
                    <FilledIconButton onClick={onClose}>
                        <CloseIcon />
                    </FilledIconButton>
                </Stack>
            </SpacedRow>
        </DialogTitle>
    );
};

const UploadProgressDragIcon: React.FC = () => (
    <Box
        component="span"
        aria-hidden
        sx={{ color: "text.muted", display: "inline-flex", flexShrink: 0 }}
    >
        <HugeiconsIcon
            icon={DragDropVerticalIcon}
            size={26}
            strokeWidth={2.8}
        />
    </Box>
);

const useUploadProgressDrag = () => {
    const { dragPosition, setDragPosition } = useUploadProgressContext();
    const dragState = useRef<DragState | undefined>(undefined);

    const handlePointerDown = (event: React.PointerEvent<HTMLElement>) => {
        if (event.button != 0 || isInteractiveTarget(event.target)) return;

        const surface = event.currentTarget;

        const rect = surface.getBoundingClientRect();
        surface.style.position = "fixed";
        surface.style.left = `${rect.left}px`;
        surface.style.top = `${rect.top}px`;
        surface.style.right = "auto";
        surface.style.bottom = "auto";
        surface.style.margin = "0";

        dragState.current = {
            pointerStartX: event.clientX,
            pointerStartY: event.clientY,
            positionStartX: rect.left,
            positionStartY: rect.top,
            currentX: rect.left,
            currentY: rect.top,
            surface,
            surfaceWidth: rect.width,
            surfaceHeight: rect.height,
        };

        event.currentTarget.setPointerCapture(event.pointerId);
        event.preventDefault();
    };

    const handlePointerMove = (event: React.PointerEvent<HTMLElement>) => {
        if (!dragState.current) return;

        const nextX =
            dragState.current.positionStartX +
            event.clientX -
            dragState.current.pointerStartX;
        const nextY =
            dragState.current.positionStartY +
            event.clientY -
            dragState.current.pointerStartY;

        const x = clamp(
            nextX,
            0,
            window.innerWidth - dragState.current.surfaceWidth,
        );
        const y = clamp(
            nextY,
            0,
            window.innerHeight - dragState.current.surfaceHeight,
        );

        dragState.current.currentX = x;
        dragState.current.currentY = y;
        dragState.current.surface.style.left = `${x}px`;
        dragState.current.surface.style.top = `${y}px`;
    };

    const handlePointerUp = (event: React.PointerEvent<HTMLElement>) => {
        if (dragState.current) {
            setDragPosition({
                x: dragState.current.currentX,
                y: dragState.current.currentY,
            });
        }
        dragState.current = undefined;
        if (event.currentTarget.hasPointerCapture(event.pointerId)) {
            event.currentTarget.releasePointerCapture(event.pointerId);
        }
    };

    return {
        dragPosition,
        dragSurfaceProps: {
            onPointerCancel: handlePointerUp,
            onPointerDown: handlePointerDown,
            onPointerMove: handlePointerMove,
            onPointerUp: handlePointerUp,
        },
    };
};

const uploadProgressSurfaceSx = {
    cursor: "grab",
    touchAction: "none",
    userSelect: "none",
    "&:active": { cursor: "grabbing" },
};

const surfacePaperPositionSx = (dragPosition: DragPosition | undefined) =>
    dragPosition
        ? {
              position: "fixed",
              left: `${dragPosition.x}px`,
              top: `${dragPosition.y}px`,
              margin: 0,
          }
        : {};

const isInteractiveTarget = (target: EventTarget) =>
    target instanceof Element &&
    Boolean(
        target.closest("button, a, input, textarea, select, [role='button']"),
    );

const clamp = (value: number, min: number, max: number) =>
    Math.min(Math.max(value, min), Math.max(min, max));

const UploadProgressSubtitleText: React.FC = () => {
    const {
        uploadPhase,
        uploadCounter,
        finishedUploads,
        preUploadSkippedFiles,
    } = useUploadProgressContext();

    return (
        <Typography
            variant="body"
            sx={{
                fontWeight: "regular",
                color: "text.muted",
                marginTop: "4px",
            }}
        >
            {subtitleText(
                uploadPhase,
                uploadCounter,
                finishedUploads,
                preUploadSkippedFiles,
            )}
        </Typography>
    );
};

const subtitleText = (
    uploadPhase: UploadPhase,
    uploadCounter: UploadCounter,
    finishedUploads: SegregatedFinishedUploads | null | undefined,
    preUploadSkippedFiles: PreUploadSkippedFile[],
) => {
    switch (uploadPhase) {
        case "preparing":
            return t("preparing");
        case "readingMetadata":
            return t("upload_reading_metadata_files");
        case "uploading":
            return t("processed_counts", {
                count: uploadCounter.finished,
                total: uploadCounter.total,
            });
        case "cancelling":
            return t("upload_cancelling");
        case "done": {
            const count = uploadedFileCount(finishedUploads);
            const notCount = notUploadedFileCount(
                finishedUploads,
                preUploadSkippedFiles,
            );
            const items: string[] = [];
            if (count) items.push(t("upload_done", { count }));
            if (notCount) items.push(t("upload_skipped", { count: notCount }));
            if (!items.length) {
                return t("upload_done", { count });
            } else {
                return formattedListJoin(items);
            }
        }
    }
};

const uploadedFileCount = (
    finishedUploads: SegregatedFinishedUploads | null | undefined,
) => {
    if (!finishedUploads) return 0;

    let c = 0;
    c += finishedUploads.get("uploaded")?.length ?? 0;
    c += finishedUploads.get("uploadedWithStaticThumbnail")?.length ?? 0;

    return c;
};

const notUploadedFileCount = (
    finishedUploads: SegregatedFinishedUploads | null | undefined,
    preUploadSkippedFiles: PreUploadSkippedFile[],
) => {
    let c = preUploadSkippedFiles.length;

    if (!finishedUploads) return c;

    c += finishedUploads.get("alreadyUploaded")?.length ?? 0;
    c += finishedUploads.get("partnerShared")?.length ?? 0;
    c += finishedUploads.get("blocked")?.length ?? 0;
    c += finishedUploads.get("failed")?.length ?? 0;
    c += finishedUploads.get("largerThanAvailableStorage")?.length ?? 0;
    c += finishedUploads.get("tooLarge")?.length ?? 0;
    c += finishedUploads.get("unsupported")?.length ?? 0;
    c += finishedUploads.get("zeroSize")?.length ?? 0;

    return c;
};

const UploadProgressBar: React.FC = () => {
    const { uploadPhase, percentComplete } = useUploadProgressContext();

    return (
        <Box>
            {(uploadPhase == "readingMetadata" ||
                uploadPhase == "uploading") && (
                <>
                    <LinearProgress
                        sx={{ height: "2px", backgroundColor: "transparent" }}
                        variant="determinate"
                        value={percentComplete}
                    />
                    <Divider />
                </>
            )}
        </Box>
    );
};

function UploadProgressDialog() {
    const {
        open,
        onClose,
        uploadPhase,
        finishedUploads,
        preUploadSkippedFiles,
    } = useUploadProgressContext();

    const [hasUnUploadedFiles, setHasUnUploadedFiles] = useState(false);

    useEffect(() => {
        setHasUnUploadedFiles(
            notUploadedFileCount(finishedUploads, preUploadSkippedFiles) > 0,
        );
    }, [finishedUploads, preUploadSkippedFiles]);

    const handleClose: DialogProps["onClose"] = (_, reason) => {
        if (reason != "backdropClick") onClose();
    };

    const preUploadSkipped = (type: PreUploadSkippedFile["type"]) =>
        preUploadSkippedFiles
            .filter((file) => file.type == type)
            .map(({ name }, index) => ({
                key: `${type}-${index}-${name}`,
                name: basename(name),
                title: name,
            }));

    return (
        <Dialog open={open} onClose={handleClose} maxWidth="xs" fullWidth>
            <UploadProgressHeader />
            {(uploadPhase == "uploading" || uploadPhase == "done") && (
                <DialogContent sx={{ "&&&": { px: 0 } }}>
                    {uploadPhase == "uploading" && <InProgressSection />}
                    <ResultSection
                        resultType="uploaded"
                        sectionTitle={t("successful_uploads")}
                    />
                    <ResultSection
                        resultType="uploadedWithStaticThumbnail"
                        sectionTitle={t("thumbnail_generation_failed")}
                        sectionInfo={t("thumbnail_generation_failed_hint")}
                    />
                    {uploadPhase == "done" && hasUnUploadedFiles && (
                        <NotUploadSectionHeader>
                            {t("file_not_uploaded_list")}
                        </NotUploadSectionHeader>
                    )}
                    <ResultSection
                        resultType="blocked"
                        sectionTitle={t("blocked_uploads")}
                        sectionInfo={<Trans i18nKey={"blocked_uploads_hint"} />}
                    />
                    <ResultSection
                        resultType="failed"
                        sectionTitle={t("failed_uploads")}
                        sectionInfo={
                            uploadPhase == "done"
                                ? undefined
                                : t("failed_uploads_hint")
                        }
                    />
                    <ResultSection
                        resultType="alreadyUploaded"
                        sectionTitle={t("ignored_uploads")}
                        sectionInfo={t("ignored_uploads_hint")}
                    />
                    <ResultSection
                        resultType="partnerShared"
                        sectionTitle={t("partner_shared_files")}
                        sectionInfo={t("partner_shared_files_hint")}
                    />
                    <ResultSection
                        resultType="largerThanAvailableStorage"
                        sectionTitle={t("insufficient_storage")}
                        sectionInfo={t("insufficient_storage_hint")}
                    />
                    <FileNameListSection
                        items={preUploadSkipped("hiddenFile")}
                        sectionTitle={t("hidden_files")}
                        sectionInfo={t("hidden_files_hint")}
                    />
                    <FileNameListSection
                        items={preUploadSkipped("failedZip")}
                        sectionTitle={t("unreadable_zip_files")}
                        sectionInfo={t("unreadable_zip_files_hint")}
                    />
                    <ResultSection
                        resultType="unsupported"
                        sectionTitle={t("unsupported_files")}
                        sectionInfo={t("unsupported_files_hint")}
                    />
                    <ResultSection
                        resultType="zeroSize"
                        sectionTitle={t("zero_size_files")}
                        sectionInfo={t("zero_size_files_hint")}
                    />
                    <ResultSection
                        resultType="tooLarge"
                        sectionTitle={t("large_files")}
                        sectionInfo={t("large_files_hint")}
                    />
                </DialogContent>
            )}
            {uploadPhase == "done" && <DoneFooter />}
        </Dialog>
    );
}

const InProgressSection: React.FC = () => {
    const { inProgressUploads, hasLivePhotos, uploadFileNames, uploadPhase } =
        useUploadProgressContext();

    const fileList = inProgressUploads;

    // @ts-expect-error Need to add types
    const renderListItem = ({ localFileID, progress }) => {
        return (
            // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
            <InProgressItemContainer key={localFileID}>
                <InProgressFileName>
                    {uploadFileNames.get(localFileID)}
                </InProgressFileName>
                {uploadPhase == "uploading" && (
                    <InProgressPercent>{`${progress}%`}</InProgressPercent>
                )}
            </InProgressItemContainer>
        );
    };

    // @ts-expect-error Need to add types
    const getItemTitle = ({ localFileID, progress }) => {
        return `${uploadFileNames.get(localFileID)} - ${progress}%`;
    };

    // @ts-expect-error Need to add types
    const generateItemKey = ({ localFileID, progress }) => {
        return `${localFileID}-${progress}`;
    };

    return (
        <SectionAccordion>
            <SectionAccordionSummary expandIcon={<ExpandMoreIcon />}>
                <TitleText
                    title={t("uploads_in_progress")}
                    count={inProgressUploads.length}
                />
            </SectionAccordionSummary>
            <SectionAccordionDetails>
                {hasLivePhotos && (
                    <SectionInfo>{t("live_photos_detected")}</SectionInfo>
                )}
                <ItemList
                    items={fileList}
                    generateItemKey={generateItemKey}
                    getItemTitle={getItemTitle}
                    renderListItem={renderListItem}
                    maxHeight={160}
                    itemSize={35}
                />
            </SectionAccordionDetails>
        </SectionAccordion>
    );
};

const InProgressItemContainer = styled("div")(({ theme }) => ({
    width: "100%",
    display: "flex",
    alignItems: "center",
    gap: theme.spacing(1.5),
}));

const InProgressFileName = styled("span")({
    flex: 1,
    minWidth: 0,
    overflow: "hidden",
    whiteSpace: "nowrap",
    textOverflow: "ellipsis",
});

const InProgressPercent = styled("span")(({ theme }) => ({
    flexShrink: 0,
    color: theme.vars.palette.text.muted,
    fontVariantNumeric: "tabular-nums",
}));

const SectionAccordion = styled((props: AccordionProps) => (
    <Accordion disableGutters elevation={0} square {...props} />
))(({ theme }) => ({
    borderTop: `1px solid ${theme.vars.palette.divider}`,
    "&:before": { display: "none" },
    "&:last-child": { borderBottom: `1px solid ${theme.vars.palette.divider}` },
}));

const SectionAccordionSummary = styled(AccordionSummary)(({ theme }) => ({
    backgroundColor: theme.vars.palette.fill.fainter,
    // AccordionSummary is a button, and for a reasons to do with MUI internal
    // that I didn't explore further, the user agent default font family is
    // getting applied in this case.
    fontFamily: "inherit",
}));

const SectionAccordionDetails = styled(AccordionDetails)(({ theme }) => ({
    padding: theme.spacing(2),
}));

const SectionInfo: React.FC<React.PropsWithChildren> = ({ children }) => (
    <Typography variant="small" sx={{ color: "text.muted", mb: 1 }}>
        {children}
    </Typography>
);

const NotUploadSectionHeader = styled("div")(
    ({ theme }) => `
    text-align: center;
    color: ${theme.vars.palette.critical.main};
    border-bottom: 1px solid ${theme.vars.palette.critical.main};
    margin:${theme.spacing(3, 2, 1)}
`,
);

interface ResultSectionProps {
    resultType: FinishedUploadType;
    sectionTitle: string;
    sectionInfo?: React.ReactNode;
}

const ResultSection: React.FC<ResultSectionProps> = ({
    resultType,
    sectionTitle,
    sectionInfo,
}) => {
    const { finishedUploads, uploadFileNames } = useUploadProgressContext();
    const fileList = finishedUploads.get(resultType);

    if (!fileList?.length) {
        return <></>;
    }

    return (
        <FileNameListSection
            items={fileList.map((fileID) => ({
                key: fileID,
                name: uploadFileNames.get(fileID)!,
            }))}
            sectionTitle={sectionTitle}
            sectionInfo={sectionInfo}
        />
    );
};

interface ResultSectionItem {
    key: string | number;
    name: string;
    /**
     * Tooltip text. Defaults to {@link name} if not provided.
     */
    title?: string;
}

interface FileNameListSectionProps {
    items: ResultSectionItem[];
    sectionTitle: string;
    sectionInfo?: React.ReactNode;
}

const FileNameListSection: React.FC<FileNameListSectionProps> = ({
    items,
    sectionTitle,
    sectionInfo,
}) => {
    if (!items.length) {
        return <></>;
    }

    const renderListItem = (item: ResultSectionItem) => (
        <ResultItemContainer>{item.name}</ResultItemContainer>
    );

    return (
        <SectionAccordion>
            <SectionAccordionSummary expandIcon={<ExpandMoreIcon />}>
                <TitleText title={sectionTitle} count={items.length} />
            </SectionAccordionSummary>
            <SectionAccordionDetails>
                {sectionInfo && <SectionInfo>{sectionInfo}</SectionInfo>}
                <ItemList
                    items={items}
                    generateItemKey={(item) => item.key}
                    getItemTitle={(item) => item.title ?? item.name}
                    renderListItem={renderListItem}
                    maxHeight={160}
                    itemSize={35}
                />
            </SectionAccordionDetails>
        </SectionAccordion>
    );
};

const ResultItemContainer = styled("div")`
    position: relative;
    top: 5px;
    display: inline-block;
    max-width: 394px;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
`;

interface TitleTextProps {
    title: string;
    count: number | undefined;
}

const TitleText: React.FC<TitleTextProps> = ({ title, count }) => (
    <Stack
        direction="row"
        // Need to reset the font weight since it gets reset by the
        // AccordionSummary (see SectionAccordionSummary).
        sx={{ gap: 1, fontWeight: "regular", alignItems: "baseline" }}
    >
        <Typography>{title}</Typography>
        <Typography variant="small" sx={{ color: "text.faint" }}>
            {"•"}
        </Typography>
        <Typography variant="small" sx={{ color: "text.faint" }}>
            {count ?? 0}
        </Typography>
    </Stack>
);

interface ItemListProps<T> {
    items: T[];
    generateItemKey: (item: T) => string | number;
    getItemTitle: (item: T) => string;
    renderListItem: (item: T) => React.JSX.Element;
    maxHeight?: number;
    itemSize?: number;
}

interface ItemData<T> {
    renderListItem: (item: T) => React.JSX.Element;
    getItemTitle: (item: T) => string;
    items: T[];
}

const createItemData: <T>(
    renderListItem: (item: T) => React.JSX.Element,
    getItemTitle: (item: T) => string,
    items: T[],
) => ItemData<T> = memoize((renderListItem, getItemTitle, items) => ({
    // TODO
    // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
    renderListItem,
    // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
    getItemTitle,
    // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
    items,
}));

// TODO: Too many non-null assertions

// @ts-expect-error "TODO: Understand and fix the type error here"
const Row: <T>({
    index,
    style,
    data,
}: ListChildComponentProps<ItemData<T>>) => ReactElement = React.memo(
    ({ index, style, data }) => {
        const { renderListItem, items, getItemTitle } = data;
        return (
            <Tooltip
                slotProps={{
                    // Reduce the vertical offset of the tooltip "popper" from
                    // the element on which the tooltip appears.
                    popper: {
                        modifiers: [
                            { name: "offset", options: { offset: [0, -14] } },
                        ],
                    },
                }}
                title={getItemTitle(items[index]!)}
                placement="bottom-start"
                enterDelay={300}
                enterNextDelay={100}
            >
                <div style={style}>{renderListItem(items[index]!)}</div>
            </Tooltip>
        );
    },
    areEqual,
);

function ItemList<T>(props: ItemListProps<T>) {
    const itemData = createItemData(
        props.renderListItem,
        props.getItemTitle,
        props.items,
    );

    const getItemKey: ListItemKeySelector<ItemData<T>> = (index, data) => {
        const { items } = data;
        return props.generateItemKey(items[index]!);
    };

    return (
        <Box sx={{ pl: 2 }}>
            <List
                itemData={itemData}
                height={Math.min(
                    props.itemSize! * props.items.length,
                    props.maxHeight!,
                )}
                width={"100%"}
                itemSize={props.itemSize!}
                itemCount={props.items.length}
                itemKey={getItemKey}
            >
                {Row}
            </List>
        </Box>
    );
}

const DoneFooter: React.FC = () => {
    const { uploadPhase, finishedUploads, retryFailed, onClose } =
        useUploadProgressContext();

    return (
        <DialogActions>
            {uploadPhase == "done" &&
                ((finishedUploads.get("failed")?.length ?? 0) > 0 ||
                (finishedUploads.get("blocked")?.length ?? 0) > 0 ? (
                    <Button fullWidth onClick={retryFailed}>
                        {t("retry_failed_uploads")}
                    </Button>
                ) : (
                    <Button fullWidth onClick={onClose}>
                        {t("close")}
                    </Button>
                ))}
        </DialogActions>
    );
};
