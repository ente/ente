import { Cancel01Icon, RotateTopRightIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Dialog } from "@mui/material";
import { SpacePostPhotoStrip } from "components/PostPhotoStrip";
import { SpacePhotoCrop } from "components/photo-crop/PhotoCrop";
import {
    cropWithAspect,
    fullImageCrop,
    rotateImageCrop,
    rotatedImageSize,
} from "components/photo-crop/geometry";
import log from "ente-base/log";
import { useBrowserBackClose } from "hooks/use-browser-back-close";
import React from "react";
import {
    spacePostPreviewImageFromEdit,
    type SpacePostPhotoEdit,
    type SpacePostPreviewImage,
} from "utils/post-image";

export interface SpaceEditablePostPhoto {
    id: number;
    imageURL: string;
    previewURL: string;
    width: number;
    height: number;
    edit?: SpacePostPhotoEdit;
}

export interface SpacePostPhotoEditResult {
    id: number;
    edit: SpacePostPhotoEdit;
    preview?: SpacePostPreviewImage;
}

const originalEdit: SpacePostPhotoEdit = { rotationDegrees: 0 };
const aspects = [
    { label: "Free", value: undefined },
    { label: "Square", value: 1 },
    { label: "3:4", value: 3 / 4 },
    { label: "16:9", value: 16 / 9 },
];
const buttonSx = {
    alignItems: "center",
    bgcolor: "transparent",
    border: 0,
    borderRadius: "999px",
    color: "inherit",
    cursor: "pointer",
    display: "inline-flex",
    font: "inherit",
    fontSize: 14,
    fontWeight: 600,
    gap: "8px",
    justifyContent: "center",
    minHeight: 44,
    px: "12px",
    "&:disabled": { opacity: 0.4, cursor: "default" },
    "&:focus-visible": { outline: "2px solid #08C225", outlineOffset: 2 },
};

export const SpacePostPhotoEditor: React.FC<{
    photos: SpaceEditablePostPhoto[];
    initialIndex: number;
    onClose: () => void;
    onDone: (results: SpacePostPhotoEditResult[], activeIndex: number) => void;
}> = ({ photos, initialIndex, onClose, onDone }) => {
    const [activeIndex, setActiveIndex] = React.useState(initialIndex);
    const [edits, setEdits] = React.useState(() =>
        photos.map((photo) => photo.edit ?? originalEdit),
    );
    const [isSaving, setIsSaving] = React.useState(false);
    const [error, setError] = React.useState<string>();
    const mounted = React.useRef(false);
    const photo = photos[activeIndex]!;
    const edit = edits[activeIndex]!;
    const size = rotatedImageSize(photo, edit.rotationDegrees);
    const crop = edit.cropArea ?? fullImageCrop(size);
    const isEdited = Boolean(
        edit.cropArea || edit.rotationDegrees || edit.aspect,
    );

    React.useEffect(() => {
        mounted.current = true;
        return () => {
            mounted.current = false;
        };
    }, []);

    useBrowserBackClose({
        open: true,
        onClose,
        stateKey: "space-post-photo-editor",
    });

    const updateEdit = (next: SpacePostPhotoEdit) => {
        setError(undefined);
        setEdits((current) =>
            current.map((item, index) => (index == activeIndex ? next : item)),
        );
    };
    const save = async () => {
        setIsSaving(true);
        setError(undefined);
        const results: SpacePostPhotoEditResult[] = [];
        try {
            for (const [index, photo] of photos.entries()) {
                const edit = edits[index]!;
                if (edit === (photo.edit ?? originalEdit)) continue;
                const preview =
                    edit.cropArea || edit.rotationDegrees
                        ? await spacePostPreviewImageFromEdit(
                              photo.imageURL,
                              edit,
                          )
                        : undefined;
                results.push({ id: photo.id, edit, preview });
                if (!mounted.current) return;
            }
            onDone(results, activeIndex);
            results.length = 0;
        } catch (error) {
            log.error("Failed to prepare edited post photos", error);
            if (mounted.current)
                setError("Couldn't apply your edits. Try again.");
        } finally {
            for (const result of results) {
                if (result.preview) URL.revokeObjectURL(result.preview.url);
            }
            if (mounted.current) setIsSaving(false);
        }
    };

    return (
        <Dialog
            open
            fullScreen
            onClose={onClose}
            onKeyDown={(event) => event.stopPropagation()}
            aria-labelledby="space-photo-editor-title"
            slotProps={{
                paper: {
                    sx: {
                        bgcolor: "#000000",
                        color: "#F2F2F2",
                        backgroundImage: "none",
                        height: "100dvh",
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                    },
                },
            }}
            sx={{ zIndex: 1400 }}
        >
            <Box
                sx={{
                    alignItems: "center",
                    display: "grid",
                    gridTemplateColumns: "1fr auto 1fr",
                    px: "16px",
                    pt: "max(6px, env(safe-area-inset-top))",
                    pb: "6px",
                    flexShrink: 0,
                }}
            >
                <Box
                    component="button"
                    type="button"
                    aria-label="Cancel photo edits"
                    onClick={onClose}
                    sx={{
                        ...buttonSx,
                        justifySelf: "start",
                        width: 44,
                        ml: "-8px",
                        p: 0,
                    }}
                >
                    <HugeiconsIcon
                        icon={Cancel01Icon}
                        size={20}
                        strokeWidth={1.8}
                    />
                </Box>
                <Box
                    id="space-photo-editor-title"
                    sx={{
                        alignItems: "center",
                        display: "flex",
                        gap: "8px",
                        fontSize: 14,
                        fontWeight: 600,
                    }}
                >
                    Edit
                    {photos.length > 1 && (
                        <Box
                            component="span"
                            sx={{
                                color: "#A6A6A6",
                                fontSize: 12,
                                fontWeight: 500,
                            }}
                        >
                            {activeIndex + 1} / {photos.length}
                        </Box>
                    )}
                </Box>
                <Box
                    component="button"
                    type="button"
                    disabled={isSaving}
                    aria-busy={isSaving}
                    onClick={() => void save()}
                    sx={{
                        ...buttonSx,
                        justifySelf: "end",
                        borderRadius: "999px",
                        p: 0,
                    }}
                >
                    <Box
                        component="span"
                        sx={{
                            alignItems: "center",
                            bgcolor: "#FFFFFF",
                            borderRadius: "999px",
                            color: "#171717",
                            display: "inline-flex",
                            height: 32,
                            px: "16px",
                        }}
                    >
                        {isSaving ? "Saving…" : "Done"}
                    </Box>
                </Box>
            </Box>
            <Box
                sx={{
                    display: "flex",
                    flex: 1,
                    minHeight: 0,
                    px: "24px",
                    py: "20px",
                    maxWidth: 1000,
                    width: "100%",
                    boxSizing: "border-box",
                    alignSelf: "center",
                }}
            >
                <SpacePhotoCrop
                    key={photo.id}
                    imageURL={photo.imageURL}
                    imageSize={photo}
                    rotation={edit.rotationDegrees}
                    crop={crop}
                    aspect={edit.aspect}
                    disabled={isSaving}
                    onChange={(cropArea) => updateEdit({ ...edit, cropArea })}
                />
            </Box>
            <Box
                sx={{
                    display: "flex",
                    flexDirection: "column",
                    alignItems: "center",
                    gap: "12px",
                    px: "12px",
                    pb: "max(16px, env(safe-area-inset-bottom))",
                    flexShrink: 0,
                }}
            >
                {error && (
                    <Box role="alert" sx={{ color: "#FF8A8A", fontSize: 13 }}>
                        {error}
                    </Box>
                )}
                <Box
                    sx={{
                        alignItems: "center",
                        display: "grid",
                        gridTemplateColumns: "44px minmax(0, 1fr) 56px",
                        gap: "6px",
                        width: "100%",
                        maxWidth: 390,
                    }}
                >
                    <Box
                        component="button"
                        type="button"
                        aria-label="Rotate photo 90 degrees clockwise"
                        title="Rotate 90°"
                        disabled={isSaving}
                        onClick={() => {
                            const rotationDegrees =
                                (edit.rotationDegrees + 90) % 360;
                            const rotatedCrop = rotateImageCrop(crop, size);
                            updateEdit({
                                ...edit,
                                rotationDegrees,
                                cropArea: edit.aspect
                                    ? cropWithAspect(
                                          rotatedCrop,
                                          edit.aspect,
                                          rotatedImageSize(
                                              photo,
                                              rotationDegrees,
                                          ),
                                      )
                                    : edit.cropArea
                                      ? rotatedCrop
                                      : undefined,
                            });
                        }}
                        sx={{ ...buttonSx, bgcolor: "#1C1C1E", p: 0 }}
                    >
                        <HugeiconsIcon
                            icon={RotateTopRightIcon}
                            size={20}
                            strokeWidth={1.8}
                        />
                    </Box>
                    <Box
                        role="group"
                        aria-label="Crop aspect ratio"
                        sx={{
                            display: "flex",
                            bgcolor: "#1C1C1E",
                            borderRadius: "999px",
                            px: "4px",
                        }}
                    >
                        {aspects.map(({ label, value }) => (
                            <Box
                                key={label}
                                component="button"
                                type="button"
                                disabled={isSaving}
                                aria-pressed={edit.aspect == value}
                                onClick={() =>
                                    updateEdit({
                                        ...edit,
                                        aspect: value,
                                        cropArea: value
                                            ? cropWithAspect(crop, value, size)
                                            : edit.cropArea,
                                    })
                                }
                                sx={{
                                    ...buttonSx,
                                    flex: "1 0 auto",
                                    fontSize: 13,
                                    p: 0,
                                    color:
                                        edit.aspect == value
                                            ? "#FFFFFF"
                                            : "#A6A6A6",
                                }}
                            >
                                <Box
                                    component="span"
                                    sx={{
                                        alignItems: "center",
                                        bgcolor:
                                            edit.aspect == value
                                                ? "#3A3A3C"
                                                : "transparent",
                                        borderRadius: "999px",
                                        boxSizing: "border-box",
                                        display: "flex",
                                        height: 36,
                                        justifyContent: "center",
                                        width: "100%",
                                        px: "10px",
                                        "@media (max-width: 359px)": {
                                            px: "6px",
                                        },
                                    }}
                                >
                                    {label}
                                </Box>
                            </Box>
                        ))}
                    </Box>
                    <Box
                        component="button"
                        type="button"
                        title="Reset edits"
                        disabled={isSaving || !isEdited}
                        onClick={() => updateEdit(originalEdit)}
                        sx={{
                            ...buttonSx,
                            bgcolor: "#1C1C1E",
                            fontSize: 13,
                            p: 0,
                            "&:disabled": {
                                opacity: 1,
                                color: "#777777",
                                cursor: "default",
                            },
                        }}
                    >
                        Reset
                    </Box>
                </Box>
                {photos.length > 1 && (
                    <Box sx={{ width: "100%", maxWidth: 390 }}>
                        <SpacePostPhotoStrip
                            activeIndex={activeIndex}
                            disabled={isSaving}
                            onSelect={setActiveIndex}
                            photos={photos.map((photo) => ({
                                id: photo.id,
                                imageUrl: photo.previewURL,
                            }))}
                        />
                    </Box>
                )}
            </Box>
        </Dialog>
    );
};
