/* TODO: Audit this file.
   All the bangs shouldn't be needed with better types / restructuring. */
/* eslint-disable @typescript-eslint/no-floating-promises */
/* eslint-disable @typescript-eslint/no-unnecessary-condition */
/* eslint-disable react-hooks/exhaustive-deps */
/* eslint-disable @typescript-eslint/prefer-promise-reject-errors */
/* eslint-disable @typescript-eslint/no-unnecessary-type-assertion */

import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import CloseIcon from "@mui/icons-material/Close";
import CloudUploadIcon from "@mui/icons-material/CloudUpload";
import CropIcon from "@mui/icons-material/Crop";
import Crop169Icon from "@mui/icons-material/Crop169";
import Crop32Icon from "@mui/icons-material/Crop32";
import CropOriginalIcon from "@mui/icons-material/CropOriginal";
import CropSquareIcon from "@mui/icons-material/CropSquare";
import DownloadIcon from "@mui/icons-material/Download";
import FlipIcon from "@mui/icons-material/Flip";
import MenuIcon from "@mui/icons-material/Menu";
import RotateLeftIcon from "@mui/icons-material/RotateLeft";
import RotateRightIcon from "@mui/icons-material/RotateRight";
import {
    Backdrop,
    Box,
    Button,
    CircularProgress,
    IconButton,
    Slider,
    Stack,
    styled,
    Tab,
    Tabs,
    Typography,
} from "@mui/material";
import type { MiniDialogAttributes } from "ente-base/components/MiniDialog";
import { SidebarDrawer } from "ente-base/components/mui/SidebarDrawer";
import {
    RowButton,
    RowButtonDivider,
    RowButtonGroup,
    RowButtonGroupTitle,
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
    useId,
    useRef,
    useState,
    type Ref,
    type RefObject,
} from "react";
import { savedCollections } from "../services/photos-fdb";

export type ImageEditorOverlayProps = ModalVisibilityProps & {
    /**
     * The (Ente) file to edit.
     */
    file: EnteFile;
    /**
     * Called when the user activates the button to save a copy of the given
     * {@link enteFile} to their Ente account with the edits they have made.
     *
     * @param editedFile A Web {@link File} containing the edited contents.
     * @param collection The collection to which the edited file should be
     * added.
     * @param enteFile The original {@link EnteFile}.
     */
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
    const titleID = useId();

    const canvasRef = useRef<HTMLCanvasElement | null>(null);
    const originalSizeCanvasRef = useRef<HTMLCanvasElement | null>(null);
    const parentRef = useRef<HTMLDivElement | null>(null);

    const [fileURL, setFileURL] = useState<string | undefined>(undefined);
    // The MIME type of the original file that we are editing.
    //
    // It should generally be present, but it is not guaranteed to be.
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

    const [showControlsDrawer, setShowControlsDrawer] = useState(true);

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
        const canvasBounds = {
            height: canvasRef.current!.height,
            width: canvasRef.current!.width,
        };
        const parentBounds = parentRef.current!.getBoundingClientRect();

        // calculate the offset created by centering the canvas in its parent
        const offsetX = (parentBounds.width - canvasBounds.width) / 2;
        const offsetY = (parentBounds.height - canvasBounds.height) / 2;

        return { offsetY, offsetX, canvasBounds, parentBounds };
    };

    const handleDragStart: React.MouseEventHandler = (e) => {
        if (currentTab != "crop") return;

        const rect = cropBoxRef.current!.getBoundingClientRect();
        const offsetX = e.pageX - rect.left - rect.width / 2;
        const offsetY = e.pageY - rect.top - rect.height / 2;

        // The threshold near the corners of the crop box in which dragging is
        // assumed as not the intention.
        const cornerThreshold = 20;

        // check if the cursor is near the corners of the box
        const isNearLeftOrRightEdge =
            e.pageX < rect.left + cornerThreshold ||
            e.pageX > rect.right - cornerThreshold;
        const isNearTopOrBottomEdge =
            e.pageY < rect.top + cornerThreshold ||
            e.pageY > rect.bottom - cornerThreshold;

        if (isNearLeftOrRightEdge && isNearTopOrBottomEdge) {
            // cursor is near a corner, do not initiate dragging
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

        // d- variables are the delta change between start and now
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

                // constrain the new position to the canvas boundaries, accounting for the offset
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
        setCropBox((prev) => {
            const { offsetX, offsetY, canvasBounds } = getCanvasBoundsOffsets();

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
            applyFilters([canvasRef.current, originalSizeCanvasRef.current!]);
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
        if (currentTab != "crop") return;
        resetCropBox();
        setShowControlsDrawer(false);
    }, [currentTab]);

    const applyFilters = async (canvases: HTMLCanvasElement[]) => {
        try {
            for (const canvas of canvases) {
                const blurSizeRatio =
                    Math.min(canvas.width, canvas.height) /
                    Math.min(
                        canvasRef.current!.width,
                        canvasRef.current!.height,
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
            // set back to 0
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
                        const scale = Math.min(
                            parentRef.current!.clientWidth / img.width,
                            parentRef.current!.clientHeight / img.height,
                        );
                        setPreviewCanvasScale(scale);

                        const width = img.width * scale;
                        const height = img.height * scale;
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

                        resetCropBox();
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

    const applyCrop = () => {
        if (!cropBoxRef.current || !canvasRef.current) return;

        const { x1, x2, y1, y2 } = getCropRegionArgs(
            cropBoxRef.current,
            canvasRef.current,
        );
        setCanvasLoading(true);
        setTransformationPerformed(true);
        cropRegionOfCanvas(canvasRef.current, x1, y1, x2, y2);
        cropRegionOfCanvas(
            originalSizeCanvasRef.current!,
            x1 / previewCanvasScale,
            y1 / previewCanvasScale,
            x2 / previewCanvasScale,
            y2 / previewCanvasScale,
        );
        resetCropBox();
        setCanvasLoading(false);

        setCurrentTab("transform");
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
                    "aria-labelledby": titleID,
                    "aria-modal": true,
                    role: "dialog",
                },
            }}
            sx={{
                backgroundColor: "background.default" /* Opaque */,
                width: "100%",
                zIndex: "var(--mui-zIndex-modal)",
            }}
            open
        >
            <Box sx={{ padding: "1rem", width: "100%", height: "100%" }}>
                <Stack
                    direction="row"
                    sx={{
                        justifyContent: "space-between",
                        alignItems: "center",
                    }}
                >
                    <Typography
                        id={titleID}
                        variant="h2"
                        sx={{ fontWeight: "medium" }}
                    >
                        {t("photo_editor")}
                    </Typography>
                    <IconButton
                        onClick={() => {
                            setShowControlsDrawer(true);
                        }}
                    >
                        <MenuIcon />
                    </IconButton>
                </Stack>
                <Stack
                    direction="row"
                    onMouseUp={handleDragEnd}
                    onMouseMove={isDragging ? handleDrag : undefined}
                    onMouseDown={handleDragStart}
                    sx={{
                        width: "100%",
                        height: "100%",
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
                        }}
                    >
                        <Stack
                            ref={parentRef}
                            direction="row"
                            sx={{
                                height: "88%",
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
                        {currentTab == "crop" && (
                            <Stack sx={{ mt: 2, alignItems: "center" }}>
                                <Button
                                    color="accent"
                                    startIcon={<CropIcon />}
                                    onClick={applyCrop}
                                >
                                    {t("apply_crop")}
                                </Button>
                            </Stack>
                        )}
                    </Box>
                </Stack>
            </Box>
            <SidebarDrawer
                variant="persistent"
                anchor="right"
                open={showControlsDrawer}
                onClose={handleCloseWithConfirmation}
            >
                <Stack direction="row" sx={{ justifyContent: "space-between" }}>
                    <IconButton
                        onClick={() => {
                            setShowControlsDrawer(false);
                        }}
                    >
                        <ChevronRightIcon />
                    </IconButton>
                    <IconButton onClick={handleCloseWithConfirmation}>
                        <CloseIcon />
                    </IconButton>
                </Stack>
                <Stack
                    direction="row"
                    sx={{ gap: "0.5rem", marginBottom: "1rem" }}
                >
                    <Tabs
                        value={currentTab}
                        onChange={(_, value) => {
                            // eslint-disable-next-line @typescript-eslint/no-unsafe-argument
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
                <RowButtonGroupTitle>{t("reset")}</RowButtonGroupTitle>
                <RowButtonGroup sx={{ mb: "0.5rem" }}>
                    <RowButton
                        disabled={canvasLoading}
                        startIcon={<CropOriginalIcon />}
                        label={t("restore_original")}
                        onClick={() => void loadCanvas()}
                    />
                </RowButtonGroup>
                {currentTab == "crop" && (
                    <CropMenu
                        {...menuProps}
                        previewScale={previewCanvasScale}
                        cropBoxProps={cropBox}
                        cropBoxRef={cropBoxRef}
                        resetCropBox={resetCropBox}
                    />
                )}
                {currentTab == "transform" && <TransformMenu {...menuProps} />}
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
                <RowButtonGroupTitle>{t("export_data")}</RowButtonGroupTitle>
                <RowButtonGroup>
                    <RowButton
                        disabled={!transformationPerformed && !coloursAdjusted}
                        startIcon={<DownloadIcon />}
                        label={t("download_edited")}
                        onClick={downloadEditedPhoto}
                    />
                    <RowButtonDivider />
                    <RowButton
                        disabled={!transformationPerformed && !coloursAdjusted}
                        startIcon={<CloudUploadIcon />}
                        label={t("save_a_copy_to_ente")}
                        onClick={saveCopyToEnte}
                    />
                </RowButtonGroup>
            </SidebarDrawer>
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

/**
 * Create a new {@link File} with the contents of the given canvas.
 *
 * @param canvas A {@link HTMLCanvasElement} whose contents we want to download
 * as a file.
 *
 * @param originalFileName The name of the original file which was used to seed
 * the canvas. This will be used as a base name for the generated file (with an
 * "-edited" suffix).
 *
 * @param originalMIMEType The MIME type of the original file which was used to
 * seed the canvas. When possible, we try to download a file in the same format,
 * but this is not guaranteed and depends on browser support. If the original
 * MIME type can not be preserved, a PNG file will be downloaded.
 */
const canvasToFile = async (
    canvas: HTMLCanvasElement,
    originalFileName: string,
    originalMIMEType?: string,
): Promise<File> => {
    const image = new Image();
    image.src = canvas.toDataURL();

    // Browsers are required to support "image/png". They may also support
    // "image/jpeg" and "image/webp". Potentially they may even support more
    // formats, but to keep this scoped we limit to these three.
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

    const blob = (await new Promise<Blob>((resolve) =>
        // eslint-disable-next-line @typescript-eslint/ban-ts-comment
        // @ts-ignore
        canvas.toBlob(resolve, mimeType),
    ))!;

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
    // get the bounding rectangle of the crop box
    const cropBoxRect = cropBoxEle.getBoundingClientRect();
    // Get the bounding rectangle of the canvas
    const canvasRect = canvasEle.getBoundingClientRect();

    // calculate the scale of the canvas display relative to its actual dimensions
    const displayScale = canvasEle.width / canvasRect.width;

    // calculate the coordinates of the crop box relative to the canvas and adjust for any scrolling by adding scroll offsets
    const x1 =
        (cropBoxRect.left - canvasRect.left + window.scrollX) * displayScale;
    const y1 =
        (cropBoxRect.top - canvasRect.top + window.scrollY) * displayScale;
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
                {/* Top overlay */}
                <CropOverlayRegionTemplate
                    // Height up to the top of the crop box.
                    sx={{ top: 0, left: 0, right: 0, height: `${cropBox.y}px` }}
                />

                {/* Bottom overlay */}
                <CropOverlayRegionTemplate
                    // Height from the bottom of the crop box to the bottom of
                    // the canvas.
                    sx={{
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: `calc(100% - ${cropBox.y + cropBox.height}px)`,
                    }}
                />

                {/* Left overlay */}
                <CropOverlayRegionTemplate
                    sx={{
                        top: `${cropBox.y}px`,
                        left: 0,
                        // Width up to the left side of the crop box.
                        width: `${cropBox.x}px`,
                        // Same height as the crop box.
                        height: `${cropBox.height}px`,
                    }}
                />

                {/* Right overlay */}
                <CropOverlayRegionTemplate
                    sx={{
                        top: `${cropBox.y}px`,
                        right: 0,
                        // Width from the right side of the crop box to the
                        // right side of the canvas.
                        width: `calc(100% - ${cropBox.x + cropBox.width}px)`,
                        // Same height as the crop box.
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

const presetAspectRatios = [
    { width: 16, height: 9, icon: <CropSquareIcon /> },
    { width: 3, height: 2, icon: <Crop32Icon /> },
    { width: 16, height: 10, icon: <Crop169Icon /> },
];

const TransformMenu: React.FC<CommonMenuProps> = ({
    canvasRef,
    originalSizeCanvasRef,
    canvasLoading,
    setCanvasLoading,
    setTransformationPerformed,
}) => {
    // Crops the canvas according to originalHeight and originalWidth without compounding
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
        <>
            <RowButtonGroupTitle>{t("aspect_ratio")}</RowButtonGroupTitle>
            <RowButtonGroup sx={{ mb: "0.5rem" }}>
                <RowButton
                    disabled={canvasLoading}
                    startIcon={<CropSquareIcon />}
                    label={t("square") + " (1:1)"}
                    onClick={createCropHandler(1, 1)}
                />
            </RowButtonGroup>
            <RowButtonGroup sx={{ mb: "1rem" }}>
                {presetAspectRatios.map((ratio, index) => (
                    <Fragment key={index}>
                        <RowButton
                            disabled={canvasLoading}
                            startIcon={ratio.icon}
                            label={`${ratio.width}:${ratio.height}`}
                            onClick={createCropHandler(
                                ratio.width,
                                ratio.height,
                            )}
                        />
                        {index !== presetAspectRatios.length - 1 && (
                            <RowButtonDivider />
                        )}
                    </Fragment>
                ))}
            </RowButtonGroup>
            <RowButtonGroup sx={{ mb: "1rem" }}>
                {presetAspectRatios.map((ratio, index) => (
                    <Fragment key={index}>
                        <RowButton
                            key={index}
                            disabled={canvasLoading}
                            startIcon={ratio.icon}
                            label={`${ratio.height}:${ratio.width}`}
                            onClick={createCropHandler(
                                ratio.height,
                                ratio.width,
                            )}
                        />
                        {index !== presetAspectRatios.length - 1 && (
                            <RowButtonDivider />
                        )}
                    </Fragment>
                ))}
            </RowButtonGroup>
            <RowButtonGroupTitle>{t("rotation")}</RowButtonGroupTitle>
            <RowButtonGroup sx={{ mb: "1rem" }}>
                <RowButton
                    disabled={canvasLoading}
                    startIcon={<RotateLeftIcon />}
                    label={t("rotate_left") + " 90˚"}
                    onClick={createRotationHandler("left")}
                />
                <RowButtonDivider />
                <RowButton
                    disabled={canvasLoading}
                    startIcon={<RotateRightIcon />}
                    label={t("rotate_right") + " 90˚"}
                    onClick={createRotationHandler("right")}
                />
            </RowButtonGroup>
            <RowButtonGroupTitle>{t("flip")}</RowButtonGroupTitle>
            <RowButtonGroup sx={{ mb: "1rem" }}>
                <RowButton
                    disabled={canvasLoading}
                    startIcon={
                        <FlipIcon style={{ transform: "rotateZ(90deg)" }} />
                    }
                    label={t("flip_vertically")}
                    onClick={createFlipCanvasHandler("vertical")}
                />
                <RowButtonDivider />
                <RowButton
                    disabled={canvasLoading}
                    startIcon={<FlipIcon />}
                    label={t("flip_horizontally")}
                    onClick={createFlipCanvasHandler("horizontal")}
                />
            </RowButtonGroup>
        </>
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
    <>
        <Box sx={{ px: "8px" }}>
            <RowButtonGroupTitle>{t("brightness")}</RowButtonGroupTitle>
            <Slider
                min={0}
                max={200}
                defaultValue={100}
                step={10}
                valueLabelDisplay="auto"
                value={props.brightness}
                marks={[{ value: 100, label: "100%" }]}
                onChange={(_, value) => {
                    props.setBrightness(value as number);
                }}
            />
            <RowButtonGroupTitle>{t("contrast")}</RowButtonGroupTitle>
            <Slider
                min={0}
                max={200}
                defaultValue={100}
                step={10}
                valueLabelDisplay="auto"
                value={props.contrast}
                onChange={(_, value) => {
                    props.setContrast(value as number);
                }}
                marks={[{ value: 100, label: "100%" }]}
            />
            <RowButtonGroupTitle>{t("blur")}</RowButtonGroupTitle>
            <Slider
                min={0}
                max={10}
                defaultValue={0}
                step={1}
                valueLabelDisplay="auto"
                value={props.blur}
                onChange={(_, value) => {
                    props.setBlur(value as number);
                }}
            />
            <RowButtonGroupTitle>{t("saturation")}</RowButtonGroupTitle>
            <Slider
                min={0}
                max={200}
                defaultValue={100}
                step={10}
                valueLabelDisplay="auto"
                value={props.saturation}
                onChange={(_, value) => {
                    props.setSaturation(value as number);
                }}
                marks={[{ value: 100, label: "100%" }]}
            />
        </Box>
        <RowButtonGroup sx={{ mb: "0.5rem" }}>
            <RowSwitch
                checked={props.invert}
                label={t("invert_colors")}
                onClick={() => {
                    props.setInvert(!props.invert);
                }}
            />
        </RowButtonGroup>
    </>
);
