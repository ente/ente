import { useBook } from "@/context/book";
import { editorToolbarButtonSx } from "@/theme/buttons";
import { toolbarColors } from "@/theme/colors";
import { Box, Button } from "@mui/material";
import { useEffect, useMemo, useRef, type RefObject } from "react";
import { EDITOR_SCROLLBAR_SX } from "./editorLayout";
import { AddPhotosIcon, CheckIcon } from "./icons";

export interface PhotoGalleryProps {
    onAddPhotos?: () => void;
    onPhotoDragStart?: (event: React.DragEvent, photoId: string) => void;
    onPhotoDragEnd?: () => void;
}

export default function PhotoGallery({
    onAddPhotos,
    onPhotoDragStart,
    onPhotoDragEnd,
    scrollRef,
}: PhotoGalleryProps & { scrollRef: RefObject<HTMLDivElement | null> }) {
    const { photos, thumbnailUrls, book, processingPhotos } = useBook(
        "photos",
        "thumbnailUrls",
        "book",
        "processingPhotos",
    );
    const previousPhotoCount = useRef(photos.length);
    const canDrag = !!onPhotoDragStart && !processingPhotos;

    useEffect(() => {
        const gallery = scrollRef.current;
        if (gallery && photos.length > previousPhotoCount.current) {
            gallery.scrollTo({ top: gallery.scrollHeight, behavior: "smooth" });
        }
        previousPhotoCount.current = photos.length;
    }, [photos.length, scrollRef]);

    const usedPhotos = useMemo(
        () =>
            new Set(
                book.pages.flatMap((page) =>
                    page.slots.map((slot) => slot.photoId),
                ),
            ),
        [book.pages],
    );

    return (
        <>
            <Box
                ref={scrollRef}
                sx={{
                    flex: 1,
                    minHeight: 0,
                    overflowY: "auto",
                    px: 2,
                    pb: 2,
                    ...EDITOR_SCROLLBAR_SX,
                }}
            >
                <Box
                    sx={{
                        display: "grid",
                        gridTemplateColumns: "repeat(3, minmax(0, 1fr))",
                        gap: 1,
                    }}
                >
                    {photos.map((photo) => (
                        <Box
                            key={photo.id}
                            data-gallery-photo={photo.id}
                            draggable={canDrag}
                            onDragStart={
                                onPhotoDragStart
                                    ? (event) =>
                                          onPhotoDragStart(event, photo.id)
                                    : undefined
                            }
                            onDragEnd={onPhotoDragEnd}
                            title={
                                usedPhotos.has(photo.id)
                                    ? `${photo.fileName} · Used in book`
                                    : photo.fileName
                            }
                            sx={{
                                position: "relative",
                                aspectRatio: "1",
                                borderRadius: "8px",
                                overflow: "hidden",
                                bgcolor: toolbarColors.background,
                                cursor: canDrag ? "grab" : "default",
                                "&:active": {
                                    cursor: canDrag ? "grabbing" : "default",
                                },
                            }}
                        >
                            <Box
                                component="img"
                                src={thumbnailUrls.get(photo.id)}
                                alt={photo.fileName}
                                loading="lazy"
                                decoding="async"
                                draggable={false}
                                sx={{
                                    width: "100%",
                                    height: "100%",
                                    objectFit: "cover",
                                    display: "block",
                                }}
                            />
                            {usedPhotos.has(photo.id) && (
                                <Box
                                    sx={{
                                        position: "absolute",
                                        right: 0,
                                        bottom: 0,
                                        width: 48,
                                        height: 48,
                                        background:
                                            "radial-gradient(ellipse at bottom right, rgba(0,0,0,0.6), rgba(0,0,0,0.2) 40%, transparent 75%)",
                                        pointerEvents: "none",
                                    }}
                                >
                                    <CheckIcon
                                        strokeWidth={3.5}
                                        sx={{
                                            position: "absolute",
                                            right: 5,
                                            bottom: 5,
                                            fontSize: 14,
                                            color: "#fff",
                                        }}
                                    />
                                </Box>
                            )}
                        </Box>
                    ))}
                </Box>
            </Box>
            {onAddPhotos && (
                <Box sx={{ p: 2 }}>
                    <Button
                        fullWidth
                        startIcon={<AddPhotosIcon />}
                        disabled={processingPhotos}
                        onClick={onAddPhotos}
                        sx={editorToolbarButtonSx}
                    >
                        Add photos
                    </Button>
                </Box>
            )}
        </>
    );
}
