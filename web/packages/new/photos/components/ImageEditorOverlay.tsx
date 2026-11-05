/* TODO: Audit this file.
   All the bangs shouldn't be needed with better types / restructuring. */
/* eslint-disable @typescript-eslint/no-unnecessary-condition */
/* eslint-disable react-hooks/exhaustive-deps */
/* eslint-disable @typescript-eslint/prefer-promise-reject-errors */

import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import CloseIcon from "@mui/icons-material/Close";
import CropIcon from "@mui/icons-material/Crop";
import DownloadIcon from "@mui/icons-material/Download";
import MenuIcon from "@mui/icons-material/Menu";
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

type OperationTab = "crop" | "transform" | "colors";

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

    const [previewCanvasScale, setPreviewCanvasScale] = useState(0);

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

    useEffect(() => {
        if (!canvasRef.current) {
            return;
        }
        try {
            void applyFilters([
                canvasRef.current,
                originalSizeCanvasRef.current!,
            ]).catch((e: unknown) => log.error("Error applying filters", e));
            setColoursAdjusted(
                brightness !== filterDefaultValues.brightness ||
                    contrast !== filterDefaultValues.contrast ||
                    blur !== filterDefaultValues.blur ||
                    saturation !== filterDefaultValues.saturation ||
                    invert !== filterDefaultValues.invert,
            );
        } catch (e) {
            log.error("Error applying filters", e);
        }
    }, [brightness, contrast, blur, saturation, invert, canvasRef, fileURL]);

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

    const applyFilters = async (canvases: HTMLCanvasElement[]) => {
        try {
            for (const canvas of canvases) {
                const blurSizeRatio =
                    Math.min(canvas.width, canvas.height) /
                    Math.max(
                        1,
                        Math.min(
                            canvasRef.current!.getBoundingClientRect().width,
                            canvasRef.current!.getBoundingClientRect().height,
                        ),
                    );
                const blurRadius = blurSizeRatio * blur;
                const filterString = `brightness(${brightness}%) contrast(${contrast}%) blur(${blurRadius}px) saturate(${saturation}%) invert(${
                    invert ? 1 : 0
                })`;
                const ctx = canvas.getContext("2d")!;
                ctx.imageSmoothingEnabled = false;

                ctx.filter = filterString;

                const image = new Image();
                image.src = fileURL!;

                await new Promise((resolve, reject) => {
                    image.onload = () => {
                        try {
                            ctx.clearRect(0, 0, canvas.width, canvas.height);
                            ctx.save();
                            ctx.drawImage(
                                image,
                                0,
                                0,
                                canvas.width,
                                canvas.height,
                            );
                            ctx.restore();
                            resolve(true);
                        } catch (e) {
                            reject(e);
                        }
                    };
                });
            }
        } catch (e) {
            log.error("Error applying filters", e);
            throw e;
        }
    };

    useEffect(() => {
        if (currentRotationAngle >= 360 || currentRotationAngle <= -360) {
            setCurrentRotationAngle(0);
        }
    }, [currentRotationAngle]);

    const resetFilters = () => {
        setBrightness(100);
        setContrast(100);
        setBlur(0);
        setSaturation(100);
        setInvert(false);
    };

    const loadCanvas = async () => {
        try {
            if (
                !canvasRef.current ||
                !parentRef.current ||
                !originalSizeCanvasRef.current
            ) {
                return;
            }

            setCanvasLoading(true);

            resetFilters();
            setCurrentRotationAngle(0);

            const img = new Image();
            const ctx = canvasRef.current.getContext("2d")!;
            ctx.imageSmoothingEnabled = false;
            if (!fileURL) {
                const sourceURLs =
                    await downloadManager.renderableSourceURLs(file);
                if (sourceURLs.type != "image") {
                    throw new Error("Image editor invoked for non-image file");
                }
                img.src = sourceURLs.imageURL;
                setFileURL(sourceURLs.imageURL);
                setMIMEType(sourceURLs.mimeType);
            } else {
                img.src = fileURL;
            }

            await new Promise((resolve, reject) => {
                img.onload = () => {
                    try {
                        setPreviewCanvasScale(1);

                        const width = img.width;
                        const height = img.height;
                        canvasRef.current!.width = width;
                        canvasRef.current!.height = height;

                        ctx?.drawImage(img, 0, 0, width, height);

                        originalSizeCanvasRef.current!.width = img.width;
                        originalSizeCanvasRef.current!.height = img.height;

                        const oSCtx =
                            originalSizeCanvasRef.current!.getContext("2d");

                        oSCtx?.drawImage(img, 0, 0, img.width, img.height);

                        setTransformationPerformed(false);
                        setColoursAdjusted(false);

                        setCanvasLoading(false);

                        setStartX(0);
                        setStartY(0);
                        setIsDragging(false);
                        setIsGrowing(false);

                        resolve(true);
                    } catch (e) {
                        reject(e);
                    }
                };
                img.onerror = (e) => {
                    reject(e);
                };
            });
        } catch (e) {
            log.error("Error loading canvas", e);
        }
    };

    useEffect(() => {
        if (!open || !file) return;
        void loadCanvas();
    }, [open, file]);

    const handleClose = () => {
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

    const getEditedFile = async () => {
        const originalSizeCanvas = originalSizeCanvasRef.current!;
        const originalFileName = fileFileName(file);
        return canvasToFile(originalSizeCanvas, originalFileName, mimeType);
    };

    const downloadEditedPhoto = async () => {
        if (!canvasRef.current) return;

        const f = await getEditedFile();
        saveAsFileAndRevokeObjectURL(URL.createObjectURL(f), f.name);
    };

    const saveCopyToEnte = async () => {
        if (!canvasRef.current) return;
        try {
            const collections = await savedCollections();
            const collection = collections.find(
                (c) => c.id == file.collectionID,
            );
            if (onSaveEditedCopy(await getEditedFile(), collection!, file)) {
                setFileURL(undefined);
            }
        } catch (e) {
            log.error("Error saving copy to ente", e);
        }
    };

    const menuProps = {
        originalSizeCanvasRef,
        canvasRef,
        setCanvasLoading,
        canvasLoading,
        setTransformationPerformed,
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
                    backgroundColor: "background.default",
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
                            {(!fileURL || canvasLoading) && (
                                <CircularProgress />
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
                        aria-label={t("hide")}
                        sx={editorIconButtonSx}
                        onClick={() => {
                            setShowControls(false);
                        }}
                    >
                        <ChevronRightIcon />
                    </IconButton>
                    <IconButton
                        aria-label={t("close")}
                        sx={editorIconButtonSx}
                        onClick={handleCloseWithConfirmation}
                    >
                        <CloseIcon />
                    </IconButton>
                </Stack>
                <Stack direction="row" sx={{ mt: 2, mb: 2, flexShrink: 0 }}>
                    <Tabs
                        sx={{
                            width: "100%",
                            "& .MuiTab-root": {
                                flex: 1,
                                textTransform: "none",
                            },
                        }}
                        value={currentTab}
                        onChange={(_, value: OperationTab) => {
                            setCurrentTab(value);
                        }}
                    >
                        <Tab label={t("crop")} value="crop" />
                        <Tab label={t("transform")} value="transform" />
                        <Tab
                            label={t("colors")}
                            value="colors"
                            disabled={transformationPerformed}
                        />
                    </Tabs>
                </Stack>
                <Box
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
                            previewScale={previewCanvasScale}
                            cropBoxProps={cropBox}
                            cropBoxRef={cropBoxRef}
                            resetCropBox={resetCropBox}
                        />
                    )}
                    {currentTab == "transform" && (
                        <TransformMenu {...menuProps} />
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
                    <Stack direction="row" spacing={1}>
                        <Button
                            sx={editorActionSx(false)}
                            disabled={canvasLoading}
                            onClick={() => void loadCanvas()}
                        >
                            {t("reset")}
                        </Button>
                        <Button
                            sx={editorActionSx(true)}
                            color="accent"
                            variant="contained"
                            disabled={
                                canvasLoading ||
                                (!transformationPerformed && !coloursAdjusted)
                            }
                            onClick={saveCopyToEnte}
                        >
                            {t("save_a_copy_to_ente")}
                        </Button>
                    </Stack>
                    <Button
                        size="small"
                        variant="text"
                        sx={{ color: "text.muted" }}
                        startIcon={<DownloadIcon />}
                        disabled={
                            canvasLoading ||
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
    originalSizeCanvasRef: RefObject<HTMLCanvasElement | null>;
    setTransformationPerformed: (v: boolean) => void;
    canvasLoading: boolean;
    setCanvasLoading: (v: boolean) => void;
    setCurrentTab: (tab: OperationTab) => void;
}

type CropMenuProps = CommonMenuProps & {
    previewScale: number;
    cropBoxProps: CropBoxProps;
    cropBoxRef: RefObject<HTMLDivElement | null>;
    resetCropBox: () => void;
};

const CropMenu: React.FC<CropMenuProps> = (props) => {
    const {
        canvasRef,
        originalSizeCanvasRef,
        canvasLoading,
        setCanvasLoading,
        setTransformationPerformed,
        setCurrentTab,
    } = props;

    return (
        <>
            <RowButtonGroupTitle>{t("freehand")}</RowButtonGroupTitle>
            <RowButtonGroup sx={{ mb: "0.5rem" }}>
                <RowButton
                    disabled={canvasLoading}
                    startIcon={<CropIcon />}
                    label={t("apply_crop")}
                    onClick={() => {
                        if (!props.cropBoxRef.current || !canvasRef.current)
                            return;

                        const { x1, x2, y1, y2 } = getCropRegionArgs(
                            props.cropBoxRef.current,
                            canvasRef.current,
                        );
                        setCanvasLoading(true);
                        setTransformationPerformed(true);
                        cropRegionOfCanvas(canvasRef.current, x1, y1, x2, y2);
                        cropRegionOfCanvas(
                            originalSizeCanvasRef.current!,
                            x1 / props.previewScale,
                            y1 / props.previewScale,
                            x2 / props.previewScale,
                            y2 / props.previewScale,
                        );
                        props.resetCropBox();
                        setCanvasLoading(false);

                        setCurrentTab("transform");
                    }}
                />
            </RowButtonGroup>
        </>
    );
};

const cropRegionOfCanvas = (
    canvas: HTMLCanvasElement,
    topLeftX: number,
    topLeftY: number,
    bottomRightX: number,
    bottomRightY: number,
    scale = 1,
) => {
    const context = canvas.getContext("2d");
    if (!context || !canvas) return;
    context.imageSmoothingEnabled = false;

    const width = (bottomRightX - topLeftX) * scale;
    const height = (bottomRightY - topLeftY) * scale;

    const img = new Image();
    img.src = canvas.toDataURL();
    img.onload = () => {
        context.clearRect(0, 0, canvas.width, canvas.height);

        canvas.width = width;
        canvas.height = height;

        context.drawImage(
            img,
            topLeftX,
            topLeftY,
            width,
            height,
            0,
            0,
            width,
            height,
        );
    };
};

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
    canvasRef,
    originalSizeCanvasRef,
    canvasLoading,
    setCanvasLoading,
    setTransformationPerformed,
}) => {
    const cropCanvas = (
        canvas: HTMLCanvasElement,
        widthRatio: number,
        heightRatio: number,
    ) => {
        const context = canvas.getContext("2d");

        const aspectRatio = widthRatio / heightRatio;

        if (!context || !canvas) return;
        context.imageSmoothingEnabled = false;

        const img = new Image();
        img.src = canvas.toDataURL();
        img.onload = () => {
            const sourceWidth = img.width;
            const sourceHeight = img.height;

            let sourceX = 0;
            let sourceY = 0;

            if (sourceWidth / sourceHeight > aspectRatio) {
                sourceX = (sourceWidth - sourceHeight * aspectRatio) / 2;
            } else {
                sourceY = (sourceHeight - sourceWidth / aspectRatio) / 2;
            }

            const newWidth = sourceWidth - 2 * sourceX;
            const newHeight = sourceHeight - 2 * sourceY;

            context.clearRect(0, 0, canvas.width, canvas.height);

            canvas.width = newWidth;
            canvas.height = newHeight;

            context.drawImage(
                img,
                sourceX,
                sourceY,
                newWidth,
                newHeight,
                0,
                0,
                newWidth,
                newHeight,
            );
        };
    };

    const flipCanvas = (
        canvas: HTMLCanvasElement,
        direction: "vertical" | "horizontal",
    ) => {
        const context = canvas.getContext("2d");
        if (!context || !canvas) return;
        context.resetTransform();
        context.imageSmoothingEnabled = false;
        const img = new Image();
        img.src = canvas.toDataURL();

        img.onload = () => {
            context.clearRect(0, 0, canvas.width, canvas.height);

            context.save();

            if (direction == "horizontal") {
                context.translate(canvas.width, 0);
                context.scale(-1, 1);
            } else {
                context.translate(0, canvas.height);
                context.scale(1, -1);
            }

            context.drawImage(img, 0, 0, canvas.width, canvas.height);

            context.restore();
        };
    };

    const rotateCanvas = (canvas: HTMLCanvasElement, angle: number) => {
        const context = canvas?.getContext("2d");
        if (!context || !canvas) return;
        context.imageSmoothingEnabled = false;

        const image = new Image();
        image.src = canvas.toDataURL();

        image.onload = () => {
            context.clearRect(0, 0, canvas.width, canvas.height);

            context.save();

            const radians = (angle * Math.PI) / 180;
            const sin = Math.sin(radians);
            const cos = Math.cos(radians);
            const newWidth =
                Math.abs(image.width * cos) + Math.abs(image.height * sin);
            const newHeight =
                Math.abs(image.width * sin) + Math.abs(image.height * cos);

            canvas.width = newWidth;
            canvas.height = newHeight;

            context.translate(canvas.width / 2, canvas.height / 2);
            context.rotate(radians);

            context.drawImage(
                image,
                -image.width / 2,
                -image.height / 2,
                image.width,
                image.height,
            );

            context.restore();
        };
    };

    const createCropHandler =
        (widthRatio: number, heightRatio: number) => () => {
            try {
                setCanvasLoading(true);
                cropCanvas(canvasRef.current!, widthRatio, heightRatio);
                cropCanvas(
                    originalSizeCanvasRef.current!,
                    widthRatio,
                    heightRatio,
                );
                setCanvasLoading(false);
                setTransformationPerformed(true);
            } catch (e) {
                log.error(
                    `crop handler failed - ${JSON.stringify({
                        widthRatio,
                        heightRatio,
                    })}`,
                    e,
                );
            }
        };
    const createRotationHandler = (rotation: "left" | "right") => () => {
        try {
            setCanvasLoading(true);
            rotateCanvas(canvasRef.current!, rotation == "left" ? -90 : 90);
            rotateCanvas(
                originalSizeCanvasRef.current!,
                rotation == "left" ? -90 : 90,
            );
            setCanvasLoading(false);
            setTransformationPerformed(true);
        } catch (e) {
            log.error(`rotation handler (${rotation}) failed`, e);
        }
    };

    const createFlipCanvasHandler =
        (direction: "vertical" | "horizontal") => () => {
            try {
                setCanvasLoading(true);
                flipCanvas(canvasRef.current!, direction);
                flipCanvas(originalSizeCanvasRef.current!, direction);
                setCanvasLoading(false);
                setTransformationPerformed(true);
            } catch (e) {
                log.error(`flip handler ${direction} failed`, e);
            }
        };

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
                                onClick={createCropHandler(width, height)}
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
                        onClick={createRotationHandler("left")}
                    />
                    <RowButtonDivider />
                    <RowButton
                        disabled={canvasLoading}
                        label={t("rotate_right") + " 90°"}
                        onClick={createRotationHandler("right")}
                    />
                </RowButtonGroup>
            </Box>
            <Box>
                <RowButtonGroupTitle>{t("flip")}</RowButtonGroupTitle>
                <RowButtonGroup>
                    <RowButton
                        disabled={canvasLoading}
                        label={t("flip_horizontally")}
                        onClick={createFlipCanvasHandler("horizontal")}
                    />
                    <RowButtonDivider />
                    <RowButton
                        disabled={canvasLoading}
                        label={t("flip_vertically")}
                        onClick={createFlipCanvasHandler("vertical")}
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
