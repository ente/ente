/* TODO: Audit this file.
   All the bangs shouldn't be needed with better types / restructuring. */
/* eslint-disable @typescript-eslint/no-unnecessary-condition */
/* eslint-disable react-hooks/exhaustive-deps */

import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import CloseIcon from "@mui/icons-material/Close";
import CropIcon from "@mui/icons-material/Crop";
import DownloadIcon from "@mui/icons-material/Download";
import MenuIcon from "@mui/icons-material/Menu";
import RestartAltIcon from "@mui/icons-material/RestartAlt";
import SaveOutlinedIcon from "@mui/icons-material/SaveOutlined";
import {
    Backdrop,
    Box,
    Button,
    CircularProgress,
    IconButton,
    Stack,
    styled,
    Tab,
    Tabs,
} from "@mui/material";
import type { MiniDialogAttributes } from "ente-base/components/MiniDialog";
import {
    RowButtonGroup as BaseRowButtonGroup,
    RowButton,
    RowButtonDivider,
    RowButtonGroupTitle,
    RowSlider,
    RowSwitch,
} from "ente-base/components/RowButton";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import { nameAndExtension } from "ente-base/file-name";
import log from "ente-base/log";
import { saveAsFileAndRevokeObjectURL } from "ente-base/utils/web";
import { downloadManager } from "ente-gallery/services/download";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { fileFileName } from "ente-media/file-metadata";
import { t } from "i18next";
import React, {
    forwardRef,
    Fragment,
    useEffect,
    useRef,
    useState,
    type Ref,
    type RefObject,
} from "react";
import { savedCollections } from "../services/photos-fdb";
import {
    editorActionSx,
    editorControlsSx,
    editorIconButtonSx,
} from "./ImageEditor.styles";

import {
    awaitLatestEditorRender,
    editorPreviewSize,
    renderEditorCanvas,
    transformEditorCanvas,
    type EditorAdjustments,
    type EditorTransform,
} from "./ImageEditor.render";
import { ImageEditorFilters } from "./ImageEditorFilters";

export type ImageEditorOverlayProps = ModalVisibilityProps & {
    file: EnteFile;
    onSaveEditedCopy: (
        editedFile: File,
        collection: Collection,
        enteFile: EnteFile,
    ) => boolean;
};

const filterDefaultValues = {
    brightness: 100,
    contrast: 100,
    blur: 0,
    saturation: 100,
    invert: false,
};

type OperationTab = "crop" | "transform" | "colors" | "filters";

interface CropBoxProps {
    x: number;
    y: number;
    width: number;
    height: number;
}

export const ImageEditorOverlay: React.FC<ImageEditorOverlayProps> = ({
    open,
    onClose,
    file,
    onSaveEditedCopy,
}) => {
    const { showMiniDialog } = useBaseContext();

    const canvasRef = useRef<HTMLCanvasElement | null>(null);
    const originalSizeCanvasRef = useRef<HTMLCanvasElement | null>(null);
    const parentRef = useRef<HTMLDivElement | null>(null);

    const sourceImageRef = useRef<HTMLImageElement | null>(null);
    const transformedRef = useRef(false);
    const loadRevisionRef = useRef(0);
    const actionBusyRef = useRef(false);
    const [editorBusy, setEditorBusy] = useState(false);
    const filterRenderRef = useRef<Promise<void>>(Promise.resolve());
    const filterRevisionRef = useRef(0);
    const [selectedFilter, setSelectedFilter] = useState("None");

    const [fileURL, setFileURL] = useState<string | undefined>(undefined);
    const [mimeType, setMIMEType] = useState<string | undefined>(undefined);

    const [currentRotationAngle, setCurrentRotationAngle] = useState(0);

    const [currentTab, setCurrentTab] = useState<OperationTab>("transform");

    const [brightness, setBrightness] = useState(
        filterDefaultValues.brightness,
    );
    const [contrast, setContrast] = useState(filterDefaultValues.contrast);
    const [blur, setBlur] = useState(filterDefaultValues.blur);
    const [saturation, setSaturation] = useState(
        filterDefaultValues.saturation,
    );
    const [invert, setInvert] = useState(filterDefaultValues.invert);

    const [transformationPerformed, setTransformationPerformed] =
        useState(false);
    const [coloursAdjusted, setColoursAdjusted] = useState(false);

    const [canvasLoading, setCanvasLoading] = useState(false);

    const [showControls, setShowControls] = useState(true);

    const [cropBox, setCropBox] = useState<CropBoxProps>({
        x: 0,
        y: 0,
        width: 100,
        height: 100,
    });

    const [startX, setStartX] = useState(0);
    const [startY, setStartY] = useState(0);

    const [beforeGrowthHeight, setBeforeGrowthHeight] = useState(0);
    const [beforeGrowthWidth, setBeforeGrowthWidth] = useState(0);

    const [isDragging, setIsDragging] = useState(false);
    const [isGrowing, setIsGrowing] = useState(false);

    const cropBoxRef = useRef<HTMLDivElement>(null);

    const getCanvasBoundsOffsets = () => {
        const canvasBounds = canvasRef.current!.getBoundingClientRect();
        const parentBounds = parentRef.current!.getBoundingClientRect();

        const offsetX = (parentBounds.width - canvasBounds.width) / 2;
        const offsetY = (parentBounds.height - canvasBounds.height) / 2;

        return { offsetY, offsetX, canvasBounds, parentBounds };
    };

    const handleDragStart: React.MouseEventHandler = (e) => {
        if (currentTab != "crop") return;

        const rect = cropBoxRef.current!.getBoundingClientRect();
        const offsetX = e.pageX - rect.left - rect.width / 2;
        const offsetY = e.pageY - rect.top - rect.height / 2;

        const cornerThreshold = 20;

        const isNearLeftOrRightEdge =
            e.pageX < rect.left + cornerThreshold ||
            e.pageX > rect.right - cornerThreshold;
        const isNearTopOrBottomEdge =
            e.pageY < rect.top + cornerThreshold ||
            e.pageY > rect.bottom - cornerThreshold;

        if (isNearLeftOrRightEdge && isNearTopOrBottomEdge) {
            setIsGrowing(true);
            setStartX(e.pageX);
            setStartY(e.pageY);
            setBeforeGrowthWidth(cropBox.width);
            setBeforeGrowthHeight(cropBox.height);
            return;
        }

        setIsDragging(true);
        setStartX(e.pageX - offsetX);
        setStartY(e.pageY - offsetY);
    };

    const handleDrag: React.MouseEventHandler = (e) => {
        if (!isDragging && !isGrowing) return;

        const dx = e.pageX - startX;
        const dy = e.pageY - startY;

        const { offsetX, offsetY, canvasBounds } = getCanvasBoundsOffsets();

        if (isGrowing) {
            setCropBox((prev) => {
                const newWidth = Math.min(
                    beforeGrowthWidth + dx,
                    canvasBounds.width - prev.x + offsetX,
                );
                const newHeight = Math.min(
                    beforeGrowthHeight + dy,
                    canvasBounds.height - prev.y + offsetY,
                );

                return { ...prev, width: newWidth, height: newHeight };
            });
        } else {
            setCropBox((prev) => {
                let newX = prev.x + dx;
                let newY = prev.y + dy;

                newX = Math.max(
                    offsetX,
                    Math.min(newX, offsetX + canvasBounds.width - prev.width),
                );
                newY = Math.max(
                    offsetY,
                    Math.min(newY, offsetY + canvasBounds.height - prev.height),
                );

                return { ...prev, x: newX, y: newY };
            });
            setStartX(e.pageX);
            setStartY(e.pageY);
        }
    };

    const handleDragEnd: React.MouseEventHandler = () => {
        setStartX(0);
        setStartY(0);

        setIsGrowing(false);
        setIsDragging(false);
    };

    const resetCropBox = () => {
        const { offsetX, offsetY, canvasBounds } = getCanvasBoundsOffsets();
        if (!canvasBounds.width || !canvasBounds.height) return;
        setCropBox((prev) => {
            return {
                ...prev,
                x: offsetX,
                y: offsetY,
                height: canvasBounds.height,
                width: canvasBounds.width,
            };
        });
    };

    const adjustments: EditorAdjustments = {
        preset: selectedFilter,
        brightness,
        contrast,
        saturation,
        blur,
        invert,
    };

    useEffect(() => {
        const canvas = canvasRef.current;
        const image = sourceImageRef.current;
        if (!open || !canvas || !image || !fileURL || transformedRef.current)
            return;
        const revision = ++filterRevisionRef.current;
        const rendering = new Promise<void>((resolve, reject) => {
            requestAnimationFrame(() => {
                if (revision !== filterRevisionRef.current) {
                    resolve();
                    return;
                }
                const bounds = canvas.getBoundingClientRect();
                void renderEditorCanvas(canvas, image, adjustments, {
                    blurScale:
                        Math.min(canvas.width, canvas.height) /
                        Math.max(1, Math.min(bounds.width, bounds.height)),
                    isCurrent: () => revision === filterRevisionRef.current,
                }).then(resolve, reject);
            });
        });
        filterRenderRef.current = rendering;
        void rendering.catch((e: unknown) => {
            if (!(e instanceof DOMException && e.name === "AbortError"))
                log.error("Error applying filters", e);
        });
        setColoursAdjusted(
            selectedFilter !== "None" ||
                brightness !== filterDefaultValues.brightness ||
                contrast !== filterDefaultValues.contrast ||
                blur !== filterDefaultValues.blur ||
                saturation !== filterDefaultValues.saturation ||
                invert !== filterDefaultValues.invert,
        );
        return () => {
            filterRevisionRef.current++;
        };
    }, [
        open,
        brightness,
        contrast,
        blur,
        saturation,
        invert,
        selectedFilter,
        fileURL,
    ]);

    useEffect(() => {
        const canvas = canvasRef.current;
        const parent = parentRef.current;
        if (!open || !canvas || !parent) return;
        const fitPreview = () => {
            const scale = Math.min(
                Math.max(0, parent.clientWidth - 16) / canvas.width,
                Math.max(0, parent.clientHeight - 16) / canvas.height,
            );
            if (!Number.isFinite(scale)) return;
            canvas.style.width = `${canvas.width * scale}px`;
            canvas.style.height = `${canvas.height * scale}px`;
        };
        fitPreview();
        const resizeObserver = new ResizeObserver(fitPreview);
        resizeObserver.observe(parent);
        const canvasObserver = new MutationObserver(fitPreview);
        canvasObserver.observe(canvas, {
            attributes: true,
            attributeFilter: ["width", "height"],
        });
        return () => {
            resizeObserver.disconnect();
            canvasObserver.disconnect();
        };
    }, [open, canvasLoading, fileURL]);

    useEffect(() => {
        if (!open || canvasLoading || !fileURL || currentTab != "crop") return;
        resetCropBox();
    }, [open, currentTab, canvasLoading, fileURL]);

    useEffect(() => {
        const canvas = canvasRef.current;
        const parent = parentRef.current;
        if (
            !open ||
            canvasLoading ||
            !fileURL ||
            currentTab != "crop" ||
            !canvas ||
            !parent
        )
            return;
        const bounds = () => {
            const image = canvas.getBoundingClientRect();
            const container = parent.getBoundingClientRect();
            return {
                x: image.left - container.left,
                y: image.top - container.top,
                width: image.width,
                height: image.height,
            };
        };
        let previous = bounds();
        const observer = new ResizeObserver(() => {
            const next = bounds();
            const old = previous;
            previous = next;
            if (!next.width || !next.height) return;
            if (!old.width || !old.height) {
                setCropBox(next);
                return;
            }
            setCropBox((crop) => ({
                x: next.x + ((crop.x - old.x) / old.width) * next.width,
                y: next.y + ((crop.y - old.y) / old.height) * next.height,
                width: (crop.width / old.width) * next.width,
                height: (crop.height / old.height) * next.height,
            }));
        });
        observer.observe(parent);
        observer.observe(canvas);
        return () => observer.disconnect();
    }, [open, currentTab, canvasLoading, fileURL]);

    const renderFullResolution = async (revision: number) => {
        const image = sourceImageRef.current!;
        const canvas = originalSizeCanvasRef.current!;
        const bounds = canvasRef.current!.getBoundingClientRect();
        canvas.width = image.width;
        canvas.height = image.height;
        await renderEditorCanvas(canvas, image, adjustments, {
            blurScale:
                Math.min(image.width, image.height) /
                Math.max(1, Math.min(bounds.width, bounds.height)),
            tiled: true,
            isCurrent: () =>
                revision === filterRevisionRef.current &&
                sourceImageRef.current === image,
        });
    };

    useEffect(() => {
        if (currentRotationAngle >= 360 || currentRotationAngle <= -360) {
            setCurrentRotationAngle(0);
        }
    }, [currentRotationAngle]);

    const resetFilters = () => {
        filterRevisionRef.current++;
        transformedRef.current = false;
        setSelectedFilter("None");
        setBrightness(100);
        setContrast(100);
        setBlur(0);
        setSaturation(100);
        setInvert(false);
    };

    const loadCanvas = async () => {
        const revision = ++loadRevisionRef.current;
        try {
            if (
                !canvasRef.current ||
                !parentRef.current ||
                !originalSizeCanvasRef.current
            )
                return;
            setCanvasLoading(true);
            resetFilters();
            setCurrentRotationAngle(0);
            let sourceURL = fileURL;
            if (!sourceURL) {
                const sourceURLs =
                    await downloadManager.renderableSourceURLs(file);
                if (sourceURLs.type !== "image")
                    throw new Error("Image editor invoked for non-image file");
                sourceURL = sourceURLs.imageURL;
                setMIMEType(sourceURLs.mimeType);
            }
            const image =
                sourceImageRef.current?.src === sourceURL
                    ? sourceImageRef.current
                    : await new Promise<HTMLImageElement>((resolve, reject) => {
                          const image = new Image();
                          image.onload = () => resolve(image);
                          image.onerror = reject;
                          image.src = sourceURL;
                      });
            if (revision !== loadRevisionRef.current) return;
            sourceImageRef.current = image;
            const size = editorPreviewSize(image.width, image.height);
            const canvas = canvasRef.current;
            canvas.width = size.width;
            canvas.height = size.height;
            const context = canvas.getContext("2d")!;
            context.imageSmoothingEnabled =
                size.width !== image.width || size.height !== image.height;
            context.drawImage(image, 0, 0, size.width, size.height);
            originalSizeCanvasRef.current.width =
                originalSizeCanvasRef.current.height = 1;
            setFileURL(sourceURL);
            setTransformationPerformed(false);
            setColoursAdjusted(false);
            setStartX(0);
            setStartY(0);
            setIsDragging(false);
            setIsGrowing(false);
        } catch (e) {
            log.error("Error loading canvas", e);
        } finally {
            if (revision === loadRevisionRef.current) setCanvasLoading(false);
        }
    };

    useEffect(() => {
        if (!open || !file) return;
        void loadCanvas();
        return () => {
            loadRevisionRef.current++;
            filterRevisionRef.current++;
        };
    }, [open, file]);

    const handleClose = () => {
        loadRevisionRef.current++;
        filterRevisionRef.current++;
        sourceImageRef.current = null;
        setFileURL(undefined);
        onClose();
    };

    const handleCloseWithConfirmation = () => {
        if (transformationPerformed || coloursAdjusted) {
            showMiniDialog(confirmEditorCloseDialogAttributes(handleClose));
        } else {
            handleClose();
        }
    };

    if (!open) {
        return <></>;
    }

    const runEditorAction = async (action: () => Promise<void>) => {
        if (canvasLoading || actionBusyRef.current) return false;
        actionBusyRef.current = true;
        setEditorBusy(true);
        try {
            await action();
            return true;
        } catch (e) {
            if (!(e instanceof DOMException && e.name === "AbortError"))
                log.error("Error editing image", e);
            return false;
        } finally {
            actionBusyRef.current = false;
            setEditorBusy(false);
        }
    };

    const handleTransform = (transform: EditorTransform) =>
        runEditorAction(async () => {
            await awaitLatestEditorRender(() => filterRenderRef.current);
            const revision = ++filterRevisionRef.current;
            if (!transformedRef.current) await renderFullResolution(revision);
            if (revision !== filterRevisionRef.current)
                throw new DOMException("Transform cancelled", "AbortError");
            transformEditorCanvas(canvasRef.current!, transform);
            transformEditorCanvas(originalSizeCanvasRef.current!, transform);
            transformedRef.current = true;
            setTransformationPerformed(true);
            setCurrentTab((tab) =>
                tab === "colors" || tab === "filters" ? "transform" : tab,
            );
        });

    const getEditedFile = async () => {
        await awaitLatestEditorRender(() => filterRenderRef.current);
        if (!transformedRef.current)
            await renderFullResolution(++filterRevisionRef.current);
        return canvasToFile(
            originalSizeCanvasRef.current!,
            fileFileName(file),
            mimeType,
        );
    };

    const downloadEditedPhoto = () =>
        runEditorAction(async () => {
            const edited = await getEditedFile();
            saveAsFileAndRevokeObjectURL(
                URL.createObjectURL(edited),
                edited.name,
            );
        });

    const saveCopyToEnte = () =>
        runEditorAction(async () => {
            const collections = await savedCollections();
            const collection = collections.find(
                (c) => c.id === file.collectionID,
            );
            if (onSaveEditedCopy(await getEditedFile(), collection!, file))
                handleClose();
        });

    const menuProps = {
        canvasRef,
        canvasLoading: canvasLoading || editorBusy,
        onTransform: handleTransform,
        setCurrentTab,
    };

    return (
        <Backdrop
            slotProps={{
                root: {
                    "aria-hidden": false,
                    "aria-label": t("photo_editor"),
                    "aria-modal": true,
                    role: "dialog",
                },
            }}
            sx={{
                backgroundColor: "#161616",
                padding: { xs: "8px", sm: "11px" },
                boxSizing: "border-box",
                width: "100%",
                display: "grid",
                gap: "11px",
                gridTemplateColumns: {
                    xs: "minmax(0, 1fr)",
                    md: showControls
                        ? "minmax(0, 1fr) minmax(0, 375px)"
                        : "minmax(0, 1fr)",
                },
                gridTemplateRows: {
                    xs: showControls
                        ? "minmax(0, 1fr) minmax(0, 45%)"
                        : "minmax(0, 1fr)",
                    md: "minmax(0, 1fr)",
                },
                zIndex: "var(--mui-zIndex-modal)",
            }}
            open
        >
            <Box
                sx={{
                    position: "relative",
                    padding: "1rem",
                    width: "100%",
                    height: "100%",
                    boxSizing: "border-box",
                    borderRadius: "20px",
                    backgroundColor: "background.paper",
                    overflow: "hidden",
                    display: "flex",
                    flexDirection: "column",
                }}
            >
                {!showControls && (
                    <IconButton
                        aria-label={t("toggle_controls")}
                        aria-expanded={false}
                        sx={{
                            position: "absolute",
                            top: "16px",
                            right: "16px",
                            zIndex: 1,
                            borderRadius: "12px",
                            bgcolor: "fill.faint",
                        }}
                        onClick={() => setShowControls(true)}
                    >
                        <MenuIcon />
                    </IconButton>
                )}
                <Stack
                    direction="row"
                    onMouseUp={handleDragEnd}
                    onMouseMove={isDragging ? handleDrag : undefined}
                    onMouseDown={handleDragStart}
                    sx={{
                        width: "100%",
                        flex: 1,
                        minHeight: 0,
                        overflow: "hidden",
                        boxSizing: "border-box",
                        alignItems: "center",
                        justifyContent: "center",
                        position: "relative",
                    }}
                >
                    <Box
                        sx={{
                            position: "relative",
                            width: "100%",
                            height: "100%",
                            display: "flex",
                            flexDirection: "column",
                        }}
                    >
                        <Stack
                            ref={parentRef}
                            direction="row"
                            sx={{
                                flex: 1,
                                minHeight: 0,
                                width: "100%",
                                alignItems: "center",
                                justifyContent: "center",
                                position: "relative",
                            }}
                        >
                            {(!fileURL || canvasLoading || editorBusy) && (
                                <CircularProgress sx={{ zIndex: 1 }} />
                            )}

                            <canvas
                                ref={canvasRef}
                                style={{
                                    objectFit: "contain",
                                    maxWidth: "calc(100% - 16px)",
                                    maxHeight: "calc(100% - 16px)",
                                    display:
                                        !fileURL || canvasLoading
                                            ? "none"
                                            : "block",
                                    position: "absolute",
                                }}
                            />
                            <canvas
                                ref={originalSizeCanvasRef}
                                style={{ display: "none" }}
                            />

                            {currentTab == "crop" && (
                                <FreehandCropRegion
                                    cropBox={cropBox}
                                    ref={cropBoxRef}
                                    setIsDragging={setIsDragging}
                                />
                            )}
                        </Stack>
                    </Box>
                </Stack>
            </Box>
            <Box
                component="aside"
                sx={[
                    editorControlsSx,
                    {
                        display: showControls ? "flex" : "none",
                        flexDirection: "column",
                        height: "100%",
                        minWidth: 0,
                        minHeight: 0,
                        overflowX: "hidden",
                        overflowY: { xs: "auto", md: "hidden" },
                        p: 2.5,
                        boxSizing: "border-box",
                        borderRadius: "20px",
                    },
                ]}
            >
                <Stack
                    direction="row"
                    sx={{ justifyContent: "space-between", flexShrink: 0 }}
                >
                    <IconButton
                        disabled={editorBusy}
                        aria-label={t("hide")}
                        sx={editorIconButtonSx}
                        onClick={() => {
                            setShowControls(false);
                        }}
                    >
                        <ChevronRightIcon />
                    </IconButton>
                    <Stack direction="row" spacing={1}>
                        <IconButton
                            aria-label={t("reset")}
                            title={t("reset")}
                            sx={editorIconButtonSx}
                            disabled={canvasLoading || editorBusy}
                            onClick={() => void loadCanvas()}
                        >
                            <RestartAltIcon />
                        </IconButton>
                        <IconButton
                            disabled={editorBusy}
                            aria-label={t("close")}
                            sx={editorIconButtonSx}
                            onClick={handleCloseWithConfirmation}
                        >
                            <CloseIcon />
                        </IconButton>
                    </Stack>
                </Stack>
                <Stack direction="row" sx={{ mt: 2, mb: 2, flexShrink: 0 }}>
                    <Tabs
                        sx={{
                            width: "100%",
                            "& .MuiTab-root": {
                                flex: 1,
                                minWidth: 0,
                                px: 0.5,
                                textTransform: "none",
                            },
                        }}
                        value={currentTab}
                        onChange={(_, value: OperationTab) => {
                            if (canvasLoading || actionBusyRef.current) return;
                            if (
                                transformedRef.current &&
                                (value === "colors" || value === "filters")
                            )
                                return;
                            setCurrentTab(value);
                        }}
                    >
                        <Tab
                            label={t("crop")}
                            value="crop"
                            disabled={canvasLoading || editorBusy}
                        />
                        <Tab
                            label={t("transform")}
                            value="transform"
                            disabled={canvasLoading || editorBusy}
                        />
                        <Tab
                            label={t("colors")}
                            value="colors"
                            disabled={
                                canvasLoading ||
                                editorBusy ||
                                transformationPerformed
                            }
                        />
                        <Tab
                            label={t("filters")}
                            value="filters"
                            disabled={
                                canvasLoading ||
                                editorBusy ||
                                transformationPerformed
                            }
                        />
                    </Tabs>
                </Stack>
                <Box
                    inert={canvasLoading || editorBusy}
                    sx={{
                        flex: { xs: "0 0 auto", md: "1 1 auto" },
                        minHeight: 0,
                        overflowY: { xs: "visible", md: "auto" },
                        pr: 0.5,
                    }}
                >
                    {currentTab == "crop" && (
                        <CropMenu
                            {...menuProps}
                            cropBoxRef={cropBoxRef}
                            resetCropBox={resetCropBox}
                        />
                    )}
                    {currentTab == "transform" && (
                        <TransformMenu {...menuProps} />
                    )}
                    {currentTab == "filters" && (
                        <ImageEditorFilters
                            fileURL={fileURL}
                            selected={selectedFilter}
                            adjustments={{
                                brightness,
                                contrast,
                                saturation,
                                blur,
                                invert,
                            }}
                            previewCanvasRef={canvasRef}
                            disabled={canvasLoading || editorBusy}
                            onSelect={setSelectedFilter}
                        />
                    )}
                    {currentTab == "colors" && (
                        <ColoursMenu
                            brightness={brightness}
                            contrast={contrast}
                            saturation={saturation}
                            blur={blur}
                            invert={invert}
                            setBrightness={setBrightness}
                            setContrast={setContrast}
                            setSaturation={setSaturation}
                            setBlur={setBlur}
                            setInvert={setInvert}
                        />
                    )}
                </Box>
                <Stack spacing={1} sx={{ pt: 2, flexShrink: 0 }}>
                    <Button
                        sx={editorActionSx(true)}
                        color="accent"
                        variant="contained"
                        startIcon={<SaveOutlinedIcon />}
                        disabled={
                            canvasLoading ||
                            editorBusy ||
                            (!transformationPerformed && !coloursAdjusted)
                        }
                        onClick={saveCopyToEnte}
                    >
                        {t("save_a_copy_to_ente")}
                    </Button>
                    <Button
                        sx={editorActionSx(false)}
                        startIcon={<DownloadIcon />}
                        disabled={
                            canvasLoading ||
                            editorBusy ||
                            (!transformationPerformed && !coloursAdjusted)
                        }
                        onClick={downloadEditedPhoto}
                    >
                        {t("download_edited")}
                    </Button>
                </Stack>
            </Box>
        </Backdrop>
    );
};

const confirmEditorCloseDialogAttributes = (
    onConfirm: () => void,
): MiniDialogAttributes => ({
    title: t("discard_changes"),
    message: t("discard_changes_message"),
    continue: { text: t("discard"), color: "critical", action: onConfirm },
});

const canvasToFile = async (
    canvas: HTMLCanvasElement,
    originalFileName: string,
    originalMIMEType?: string,
): Promise<File> => {
    const image = new Image();
    image.src = canvas.toDataURL();

    // PNG is guaranteed; preserve JPEG or WebP when possible.
    let [mimeType, extension] = ["image/png", "png"];
    switch (originalMIMEType) {
        case "image/jpeg":
            mimeType = originalMIMEType;
            extension = "jpeg";
            break;
        case "image/webp":
            mimeType = originalMIMEType;
            extension = "webp";
            break;
        default:
            break;
    }

    const blob = await new Promise<Blob | null>((resolve) =>
        canvas.toBlob(resolve, mimeType),
    );
    if (!blob) throw new Error("Failed to encode edited image");

    const [originalName] = nameAndExtension(originalFileName);
    const fileName = `${originalName}-edited.${extension}`;

    log.debug(() => ["canvas => file", { blob, type: blob.type, mimeType }]);

    return new File([blob], fileName);
};

interface CommonMenuProps {
    canvasRef: RefObject<HTMLCanvasElement | null>;
    canvasLoading: boolean;
    onTransform: (transform: EditorTransform) => Promise<boolean>;
    setCurrentTab: (tab: OperationTab) => void;
}

type CropMenuProps = CommonMenuProps & {
    cropBoxRef: RefObject<HTMLDivElement | null>;
    resetCropBox: () => void;
};

const CropMenu: React.FC<CropMenuProps> = ({
    canvasRef,
    canvasLoading,
    onTransform,
    setCurrentTab,
    cropBoxRef,
    resetCropBox,
}) => (
    <>
        <RowButtonGroupTitle>{t("freehand")}</RowButtonGroupTitle>
        <RowButtonGroup sx={{ mb: "0.5rem" }}>
            <RowButton
                disabled={canvasLoading}
                startIcon={<CropIcon />}
                label={t("apply_crop")}
                onClick={async () => {
                    const canvas = canvasRef.current;
                    if (!cropBoxRef.current || !canvas) return;
                    const { x1, x2, y1, y2 } = getCropRegionArgs(
                        cropBoxRef.current,
                        canvas,
                    );
                    const clamp = (value: number) =>
                        Math.max(0, Math.min(1, value));
                    if (
                        await onTransform({
                            type: "crop",
                            left: clamp(x1 / canvas.width),
                            top: clamp(y1 / canvas.height),
                            right: clamp(x2 / canvas.width),
                            bottom: clamp(y2 / canvas.height),
                        })
                    ) {
                        resetCropBox();
                        setCurrentTab("transform");
                    }
                }}
            />
        </RowButtonGroup>
    </>
);

const getCropRegionArgs = (
    cropBoxEle: HTMLDivElement,
    canvasEle: HTMLCanvasElement,
) => {
    const cropBoxRect = cropBoxEle.getBoundingClientRect();
    const canvasRect = canvasEle.getBoundingClientRect();

    const displayScale = canvasEle.width / canvasRect.width;

    const x1 = (cropBoxRect.left - canvasRect.left) * displayScale;
    const y1 = (cropBoxRect.top - canvasRect.top) * displayScale;
    const x2 = x1 + cropBoxRect.width * displayScale;
    const y2 = y1 + cropBoxRect.height * displayScale;

    return { x1, x2, y1, y2 };
};

interface FreehandCropRegionProps {
    cropBox: CropBoxProps;
    setIsDragging: (v: boolean) => void;
}

const FreehandCropRegion = forwardRef(
    (
        { cropBox, setIsDragging }: FreehandCropRegionProps,
        ref: Ref<HTMLDivElement>,
    ) => {
        return (
            <>
                <CropOverlayRegionTemplate
                    sx={{ top: 0, left: 0, right: 0, height: `${cropBox.y}px` }}
                />

                <CropOverlayRegionTemplate
                    sx={{
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: `calc(100% - ${cropBox.y + cropBox.height}px)`,
                    }}
                />

                <CropOverlayRegionTemplate
                    sx={{
                        top: `${cropBox.y}px`,
                        left: 0,
                        width: `${cropBox.x}px`,
                        height: `${cropBox.height}px`,
                    }}
                />

                <CropOverlayRegionTemplate
                    sx={{
                        top: `${cropBox.y}px`,
                        right: 0,
                        width: `calc(100% - ${cropBox.x + cropBox.width}px)`,
                        height: `${cropBox.height}px`,
                    }}
                />

                <div
                    style={{
                        display: "grid",
                        position: "absolute",
                        left: `${cropBox.x}px`,
                        top: `${cropBox.y}px`,
                        width: `${cropBox.width}px`,
                        height: `${cropBox.height}px`,
                        border: "1px solid white",
                        gridTemplateColumns: "1fr 1fr 1fr",
                        gridTemplateRows: "1fr 1fr 1fr",
                        gap: "0px",
                    }}
                    ref={ref}
                >
                    {Array.from({ length: 9 }).map((_, index) => (
                        <Box
                            key={index}
                            sx={{
                                border: "1px solid",
                                borderColor: "white",
                                boxSizing: "border-box",
                                pointerEvents: "none",
                            }}
                        ></Box>
                    ))}

                    <Box
                        sx={{
                            position: "absolute",
                            height: "10px",
                            width: "10px",
                            backgroundColor: "white",
                            border: "1px solid",
                            borderColor: "black",
                            right: "-5px",
                            bottom: "-5px",
                            cursor: "se-resize",
                        }}
                        onMouseDown={(e) => {
                            e.preventDefault();
                            setIsDragging(true);
                        }}
                    ></Box>
                </div>
            </>
        );
    },
);

const CropOverlayRegionTemplate = styled("div")({
    position: "absolute",
    backgroundColor: "rgba(0 0 0 / 0.5)",
    pointerEvents: "none",
});

const RowButtonGroup = styled(BaseRowButtonGroup)(({ theme }) => ({
    backgroundColor: theme.vars.palette.secondary.main,
    borderRadius: 20,
    overflow: "hidden",
    "& > button, & > button:not(:last-of-type), & > button:not(:first-of-type)":
        {
            borderRadius: 0,
            minHeight: 58,
            backgroundColor: "transparent",
            "&:hover": { backgroundColor: theme.vars.palette.secondary.dark },
            "&.Mui-focusVisible": {
                outline: "2px solid",
                outlineColor: "var(--mui-palette-text-base)",
                outlineOffset: -2,
            },
        },
}));

const presetAspectRatios = [
    { width: 1, height: 1 },
    { width: 16, height: 9 },
    { width: 3, height: 2 },
    { width: 16, height: 10 },
    { width: 4, height: 5 },
    { width: 9, height: 16 },
    { width: 2, height: 3 },
    { width: 10, height: 16 },
];

const TransformMenu: React.FC<CommonMenuProps> = ({
    canvasLoading,
    onTransform,
}) => {
    return (
        <Stack spacing={2.5}>
            <Box>
                <RowButtonGroupTitle>{t("aspect_ratio")}</RowButtonGroupTitle>
                <Box
                    sx={{
                        display: "grid",
                        gridTemplateColumns: "repeat(2, minmax(0, 1fr))",
                        gap: 1,
                    }}
                >
                    {presetAspectRatios.map(({ width, height }) => (
                        <RowButtonGroup key={`${width}:${height}`}>
                            <RowButton
                                disabled={canvasLoading}
                                onClick={() =>
                                    void onTransform({
                                        type: "aspect-ratio",
                                        width,
                                        height,
                                    })
                                }
                                startIcon={
                                    <Box
                                        sx={{
                                            width: 26,
                                            height: 26,
                                            display: "grid",
                                            placeItems: "center",
                                        }}
                                    >
                                        <Box
                                            sx={{
                                                width:
                                                    22 *
                                                    Math.min(1, width / height),
                                                height:
                                                    22 *
                                                    Math.min(1, height / width),
                                                border: "1.5px solid",
                                                borderColor: "text.muted",
                                                borderRadius: "3px",
                                            }}
                                        />
                                    </Box>
                                }
                                label={
                                    width === height
                                        ? t("square")
                                        : `${width}:${height}`
                                }
                            />
                        </RowButtonGroup>
                    ))}
                </Box>
            </Box>
            <Box>
                <RowButtonGroupTitle>{t("rotation")}</RowButtonGroupTitle>
                <RowButtonGroup>
                    <RowButton
                        disabled={canvasLoading}
                        label={t("rotate_left") + " 90°"}
                        onClick={() =>
                            void onTransform({
                                type: "rotate",
                                direction: "left",
                            })
                        }
                    />
                    <RowButtonDivider />
                    <RowButton
                        disabled={canvasLoading}
                        label={t("rotate_right") + " 90°"}
                        onClick={() =>
                            void onTransform({
                                type: "rotate",
                                direction: "right",
                            })
                        }
                    />
                </RowButtonGroup>
            </Box>
            <Box>
                <RowButtonGroupTitle>{t("flip")}</RowButtonGroupTitle>
                <RowButtonGroup>
                    <RowButton
                        disabled={canvasLoading}
                        label={t("flip_horizontally")}
                        onClick={() =>
                            void onTransform({
                                type: "flip",
                                direction: "horizontal",
                            })
                        }
                    />
                    <RowButtonDivider />
                    <RowButton
                        disabled={canvasLoading}
                        label={t("flip_vertically")}
                        onClick={() =>
                            void onTransform({
                                type: "flip",
                                direction: "vertical",
                            })
                        }
                    />
                </RowButtonGroup>
            </Box>
        </Stack>
    );
};

interface ColoursMenuProps {
    brightness: number;
    contrast: number;
    saturation: number;
    blur: number;
    invert: boolean;
    setBrightness: (v: number) => void;
    setContrast: (v: number) => void;
    setSaturation: (v: number) => void;
    setBlur: (v: number) => void;
    setInvert: (v: boolean) => void;
}

const ColoursMenu: React.FC<ColoursMenuProps> = (props) => (
    <Box sx={{ pt: 2.5 }}>
        <RowButtonGroupTitle>{t("colors")}</RowButtonGroupTitle>
        <RowButtonGroup>
            {(
                [
                    [
                        "brightness",
                        props.brightness,
                        props.setBrightness,
                        200,
                        10,
                    ],
                    ["contrast", props.contrast, props.setContrast, 200, 10],
                    [
                        "saturation",
                        props.saturation,
                        props.setSaturation,
                        200,
                        10,
                    ],
                    ["blur", props.blur, props.setBlur, 10, 1],
                ] as const
            ).map(([label, value, onChange, max, step]) => (
                <Fragment key={label}>
                    <RowSlider
                        label={t(label)}
                        value={value}
                        onChange={onChange}
                        min={0}
                        max={max}
                        step={step}
                        unit={label === "blur" ? "" : "%"}
                    />
                    <RowButtonDivider />
                </Fragment>
            ))}
            <RowSwitch
                checked={props.invert}
                label={t("invert_colors")}
                onClick={() => props.setInvert(!props.invert)}
            />
        </RowButtonGroup>
    </Box>
);
