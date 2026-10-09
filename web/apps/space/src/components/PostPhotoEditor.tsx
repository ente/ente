import { Cancel01Icon, RotateTopRightIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Dialog } from "@mui/material";
import { SpacePostPhotoInput } from "components/PostPhotoInput";
import { SpacePostPhotoStrip } from "components/PostPhotoStrip";
import { SpacePostVideoEditor } from "components/PostVideoEditor";
import { SpaceVideoError } from "components/VideoError";
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
    spaceControlBackgroundHover,
    spaceSurface,
    spaceText,
    spaceTextMuted,
} from "styles/colors";
import {
    spacePostPreviewImageFromEdit,
    type SpacePostPhotoEdit,
    type SpacePostPreviewImage,
} from "utils/post-image";
import { maxSpacePostPhotos, movePostPhoto } from "utils/post-photos";
import { spaceVideoCover, type SpacePostVideoEdit } from "utils/post-video";

export interface SpaceEditablePostPhoto {
    id: number;
    imageURL: string;
    previewURL: string;
    width: number;
    height: number;
    isLoading?: boolean;
    preparationError?: string;
    isVideo?: boolean;
    edit?: SpacePostPhotoEdit;
    video?: {
        file: File;
        sourceURL: string;
        duration: number;
        edit: SpacePostVideoEdit;
    };
}

export interface SpacePostPhotoEditResult {
    id: number;
    edit: SpacePostPhotoEdit;
    videoEdit?: SpacePostVideoEdit;
    preview?: SpacePostPreviewImage;
}

const originalEdit: SpacePostPhotoEdit = { rotationDegrees: 0 };
const aspects = [
    { label: "Free", value: undefined },
    { label: "Square", value: 1 },
    { label: "3:4", value: 3 / 4 },
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
    onAdd: (files: File[]) => void;
    onClose: () => void;
    onDone: (
        results: SpacePostPhotoEditResult[],
        activeIndex: number,
        photoIDs: number[],
    ) => void;
}> = ({ photos: initialPhotos, initialIndex, onAdd, onClose, onDone }) => {
    const [photos, setPhotos] = React.useState(initialPhotos);
    const [activeID, setActiveID] = React.useState(
        initialPhotos[initialIndex]!.id,
    );
    const [edits, setEdits] = React.useState<
        Record<number, SpacePostPhotoEdit>
    >({});
    const [videoEdits, setVideoEdits] = React.useState<
        Record<number, SpacePostVideoEdit>
    >({});
    const inputRef = React.useRef<HTMLInputElement>(null);
    const knownIDs = React.useRef(new Set(initialPhotos.map(({ id }) => id)));
    const [isSaving, setIsSaving] = React.useState(false);
    const [error, setError] = React.useState<string>();
    const mounted = React.useRef(false);
    const activeIndex = photos.findIndex(({ id }) => id == activeID);
    const photo = photos[activeIndex]!;
    const edit = edits[photo.id] ?? photo.edit ?? originalEdit;
    const preparationError = photos.find(
        (photo) => photo.preparationError,
    )?.preparationError;
    const isPreparing = photos.some((photo) => photo.isLoading);
    const showPhotoStrip = photos.length > 1;
    const aspectIndex = aspects.findIndex(({ value }) => value == edit.aspect);
    const size = rotatedImageSize(photo, edit.rotationDegrees);
    const crop = edit.cropArea ?? fullImageCrop(size);
    const isEdited = Boolean(
        edit.cropArea || edit.rotationDegrees || edit.aspect,
    );

    React.useEffect(() => {
        const added = initialPhotos.filter(
            ({ id }) => !knownIDs.current.has(id),
        );
        initialPhotos.forEach(({ id }) => knownIDs.current.add(id));
        setPhotos((current) => [
            ...current.map(
                (photo) =>
                    initialPhotos.find(({ id }) => id == photo.id) ?? photo,
            ),
            ...added,
        ]);
        if (added.length) setActiveID(added[0]!.id);
    }, [initialPhotos]);

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
        setEdits((current) => ({ ...current, [photo.id]: next }));
    };
    const movePhoto = (from: number, to: number) => {
        setPhotos((current) => movePostPhoto(current, from, to));
        setActiveID(photos[from]!.id);
    };
    const removePhoto = () => {
        const remaining = photos.filter(({ id }) => id != photo.id);
        setPhotos(remaining);
        setActiveID(remaining[Math.min(activeIndex, remaining.length - 1)]!.id);
        setError(undefined);
    };
    const save = async () => {
        setIsSaving(true);
        setError(undefined);
        const results: SpacePostPhotoEditResult[] = [];
        try {
            for (const photo of photos) {
                const edit = edits[photo.id] ?? photo.edit ?? originalEdit;
                const videoEdit = videoEdits[photo.id] ?? photo.video?.edit;
                if (photo.video && videoEdit) {
                    if (videoEdit === photo.video.edit) continue;
                    const cover = await spaceVideoCover(
                        photo.video.file,
                        videoEdit.coverTime,
                    );
                    const preview = {
                        url: URL.createObjectURL(cover.file),
                        width: cover.width,
                        height: cover.height,
                    };
                    results.push({ id: photo.id, edit, videoEdit, preview });
                    if (!mounted.current) return;
                    continue;
                }
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
            onDone(
                results,
                activeIndex,
                photos.map((photo) => photo.id),
            );
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
                        color: spaceText,
                        backgroundImage: "none",
                        height: "100dvh",
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                    },
                },
            }}
            sx={{ zIndex: 1400 }}
        >
            <SpacePostPhotoInput
                inputRef={inputRef}
                onSelect={onAdd}
                remaining={maxSpacePostPhotos - photos.length}
            />
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
                    aria-label="Cancel edits"
                    onClick={onClose}
                    sx={{
                        ...buttonSx,
                        color: "#C0C0C0",
                        justifySelf: "start",
                        width: 44,
                        ml: "-12px",
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
                    sx={{ fontSize: 14, fontWeight: 600 }}
                >
                    Edit
                </Box>
                <Box
                    component="button"
                    type="button"
                    disabled={
                        isSaving || isPreparing || Boolean(preparationError)
                    }
                    aria-busy={isSaving}
                    onClick={() => void save()}
                    sx={{ ...buttonSx, justifySelf: "end", p: 0 }}
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
                inert={isSaving}
                sx={{
                    display: "flex",
                    flex: 1,
                    minHeight: 0,
                    px: photo.video ? 0 : "24px",
                    py: photo.video ? 0 : "20px",
                    maxWidth: 1000,
                    width: "100%",
                    boxSizing: "border-box",
                    alignSelf: "center",
                }}
            >
                {photo.isLoading || photo.preparationError ? (
                    <Box
                        className="space-photo-placeholder"
                        role="status"
                        aria-label={
                            photo.isLoading ? "Preparing preview" : undefined
                        }
                        aria-busy={photo.isLoading || undefined}
                        sx={{
                            width: "100%",
                            height: "100%",
                            display: "grid",
                            placeItems: "center",
                        }}
                    >
                        {photo.preparationError && (
                            <Box sx={{ maxWidth: 300, p: "24px" }}>
                                {photo.isVideo ? (
                                    <SpaceVideoError
                                        message={photo.preparationError}
                                    />
                                ) : (
                                    <Box
                                        role="alert"
                                        sx={{
                                            textAlign: "center",
                                            textWrap: "balance",
                                        }}
                                    >
                                        {photo.preparationError}
                                    </Box>
                                )}
                            </Box>
                        )}
                    </Box>
                ) : photo.video ? (
                    <SpacePostVideoEditor
                        key={photo.id}
                        file={photo.video.file}
                        sourceURL={photo.video.sourceURL}
                        duration={photo.video.duration}
                        edit={videoEdits[photo.id] ?? photo.video.edit}
                        onChange={(next) =>
                            setVideoEdits((current) => ({
                                ...current,
                                [photo.id]: next,
                            }))
                        }
                    />
                ) : (
                    <SpacePhotoCrop
                        key={photo.id}
                        imageURL={photo.imageURL}
                        imageSize={photo}
                        rotation={edit.rotationDegrees}
                        crop={crop}
                        aspect={edit.aspect}
                        disabled={isSaving}
                        onChange={(cropArea) =>
                            updateEdit({ ...edit, cropArea })
                        }
                    />
                )}
            </Box>
            <Box
                sx={{
                    display: "flex",
                    flexDirection: "column",
                    alignItems: "center",
                    gap: "12px",
                    px: "12px",
                    pt: photo.video && (error || showPhotoStrip) ? "12px" : 0,
                    pb: "max(16px, env(safe-area-inset-bottom))",
                    flexShrink: 0,
                }}
            >
                {error && (
                    <Box role="alert" sx={{ color: "#FF8A8A", fontSize: 13 }}>
                        {error}
                    </Box>
                )}
                {!photo.video && photo.imageURL && (
                    <Box
                        sx={{
                            alignItems: "center",
                            display: "grid",
                            gridTemplateColumns: "44px minmax(0, 1fr) auto",
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
                            sx={{ ...buttonSx, bgcolor: spaceSurface, p: 0 }}
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
                                position: "relative",
                                display: "flex",
                                bgcolor: spaceSurface,
                                borderRadius: "999px",
                                px: "4px",
                            }}
                        >
                            <Box
                                aria-hidden="true"
                                hidden={aspectIndex < 0}
                                sx={{
                                    position: "absolute",
                                    top: 4,
                                    bottom: 4,
                                    left: 4,
                                    width: `calc((100% - 8px) / ${aspects.length})`,
                                    bgcolor: spaceControlBackgroundHover,
                                    borderRadius: "999px",
                                    pointerEvents: "none",
                                    transform: `translateX(${aspectIndex * 100}%)`,
                                    transition: "transform 200ms ease",
                                    "@media (prefers-reduced-motion: reduce)": {
                                        transition: "none",
                                    },
                                }}
                            />
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
                                                ? cropWithAspect(
                                                      crop,
                                                      value,
                                                      size,
                                                  )
                                                : edit.cropArea,
                                        })
                                    }
                                    sx={{
                                        ...buttonSx,
                                        position: "relative",
                                        flex: 1,
                                        minWidth: 0,
                                        fontSize: 13,
                                        p: 0,
                                        color:
                                            edit.aspect == value
                                                ? "#FFFFFF"
                                                : spaceTextMuted,
                                    }}
                                >
                                    {label}
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
                                bgcolor: spaceSurface,
                                fontSize: 13,
                                px: "16px",
                                py: 0,
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
                )}
                {showPhotoStrip && (
                    <Box sx={{ width: "100%", maxWidth: 390 }}>
                        <SpacePostPhotoStrip
                            activeIndex={activeIndex}
                            disabled={isSaving}
                            onAdd={() => inputRef.current?.click()}
                            onMove={movePhoto}
                            onRemove={
                                photos.length > 1 ? removePhoto : undefined
                            }
                            onSelect={(index) => setActiveID(photos[index]!.id)}
                            photos={photos.map((photo) => ({
                                id: photo.id,
                                imageUrl: photo.previewURL,
                                isLoading: photo.isLoading,
                                hasError: Boolean(photo.preparationError),
                                isVideo: photo.isVideo,
                                durationMs: photo.video
                                    ? photo.video.duration * 1000
                                    : undefined,
                            }))}
                        />
                    </Box>
                )}
            </Box>
        </Dialog>
    );
};
