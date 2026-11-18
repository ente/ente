import { useBook } from "@/context/book";
import { getPreview } from "@/lib/db";
import { editorToolbarButtonSx } from "@/theme/buttons";
import { popupShadow, toolbarColors } from "@/theme/colors";
import {
    Backdrop,
    Box,
    Button,
    Fade,
    Popper,
    Portal,
    useMediaQuery,
} from "@mui/material";
import type { Instance } from "@popperjs/core";
import {
    useCallback,
    useEffect,
    useLayoutEffect,
    useMemo,
    useRef,
    useState,
    type RefObject,
} from "react";
import { EDITOR_SCROLLBAR_SX } from "./editorLayout";
import { AddPhotosIcon } from "./icons";

export interface PhotoGalleryProps {
    previewContainerRef: RefObject<HTMLElement | null>;
    onAddPhotos?: () => void;
    onPhotoDragStart?: (event: React.DragEvent, photoId: string) => void;
    onPhotoDragEnd?: () => void;
}

export default function PhotoGallery({
    previewContainerRef,
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
    const previewTimer = useRef<ReturnType<typeof setTimeout> | undefined>(
        undefined,
    );
    const [preview, setPreview] = useState<{
        photoId: string;
        anchor: HTMLElement;
    } | null>(null);
    const canDrag = !!onPhotoDragStart && !processingPhotos;

    const hidePreview = useCallback(() => {
        clearTimeout(previewTimer.current);
        setPreview(null);
    }, []);

    useEffect(() => {
        const handleKeyDown = (event: KeyboardEvent) => {
            if (event.key === "Escape") hidePreview();
        };
        document.addEventListener("keydown", handleKeyDown);
        return () => {
            clearTimeout(previewTimer.current);
            document.removeEventListener("keydown", handleKeyDown);
        };
    }, [hidePreview]);

    useEffect(() => {
        const gallery = scrollRef.current;
        if (gallery && photos.length > previousPhotoCount.current) {
            gallery.scrollTo({ top: gallery.scrollHeight, behavior: "smooth" });
        }
        previousPhotoCount.current = photos.length;
    }, [photos.length, scrollRef]);

    const photoPages = useMemo(() => {
        const result = new Map<string, (string | number)[]>();
        book.pages.forEach((page, index) => {
            const label =
                index === 0
                    ? "Cover"
                    : index === book.pages.length - 1
                      ? "Back cover"
                      : index;
            const photoIds = new Set(page.slots.map((slot) => slot.photoId));
            for (const photoId of photoIds) {
                if (!photoId) continue;
                const pages = result.get(photoId) ?? [];
                pages.push(label);
                result.set(photoId, pages);
            }
        });
        return result;
    }, [book.pages]);

    return (
        <>
            <Box
                ref={scrollRef}
                onScroll={hidePreview}
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
                    {photos.map((photo) => {
                        const pages = photoPages.get(photo.id) ?? [];
                        const badges =
                            pages.length > 3
                                ? [...pages.slice(0, 2), `+${pages.length - 2}`]
                                : pages;
                        return (
                            <Box
                                key={photo.id}
                                data-gallery-photo={photo.id}
                                data-previewing={preview?.photoId === photo.id}
                                draggable={canDrag}
                                onPointerEnter={(event) => {
                                    if (
                                        event.pointerType !== "mouse" ||
                                        event.buttons
                                    )
                                        return;
                                    const anchor = event.currentTarget;
                                    previewTimer.current = setTimeout(
                                        () =>
                                            setPreview({
                                                photoId: photo.id,
                                                anchor,
                                            }),
                                        300,
                                    );
                                }}
                                onPointerLeave={hidePreview}
                                onPointerDown={hidePreview}
                                onDragStart={
                                    onPhotoDragStart
                                        ? (event) => {
                                              hidePreview();
                                              onPhotoDragStart(event, photo.id);
                                          }
                                        : undefined
                                }
                                onDragEnd={onPhotoDragEnd}
                                aria-label={
                                    pages.length > 0
                                        ? `${photo.fileName} · ${pages.map((page) => (typeof page === "number" ? `Page ${page}` : page)).join(", ")}`
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
                                        cursor: canDrag
                                            ? "grabbing"
                                            : "default",
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
                                {badges.length > 0 && (
                                    <Box
                                        sx={{
                                            position: "absolute",
                                            right: 5,
                                            bottom: 5,
                                            left: 5,
                                            display: "flex",
                                            flexWrap: "wrap",
                                            justifyContent: "flex-end",
                                            gap: "3px",
                                            pointerEvents: "none",
                                        }}
                                    >
                                        {badges.map((label) => (
                                            <Box
                                                key={label}
                                                component="span"
                                                sx={{
                                                    display: "inline-flex",
                                                    alignItems: "center",
                                                    justifyContent: "center",
                                                    flexShrink: 0,
                                                    minWidth: 18,
                                                    height: 18,
                                                    px:
                                                        typeof label ===
                                                        "number"
                                                            ? 0
                                                            : "5px",
                                                    borderRadius: "999px",
                                                    bgcolor:
                                                        toolbarColors.background,
                                                    color: "#D6D6D6",
                                                    fontSize: 9,
                                                    fontWeight: 800,
                                                    lineHeight: 1,
                                                    fontVariantNumeric:
                                                        "tabular-nums",
                                                    boxShadow:
                                                        "0 1px 4px rgba(0,0,0,0.2)",
                                                }}
                                            >
                                                {label}
                                            </Box>
                                        ))}
                                    </Box>
                                )}
                            </Box>
                        );
                    })}
                </Box>
            </Box>
            {preview && previewContainerRef.current && (
                <PhotoPreview
                    key={preview.photoId}
                    {...preview}
                    container={previewContainerRef.current}
                />
            )}
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

function PhotoPreview({
    photoId,
    anchor,
    container,
}: {
    photoId: string;
    anchor: HTMLElement;
    container: HTMLElement;
}) {
    const { thumbnailUrls, getPhoto } = useBook("thumbnailUrls", "getPhoto");
    const popperRef = useRef<Instance>(null);
    const [size, setSize] = useState({ width: 0, height: 0 });
    const [source, setSource] = useState<string>();
    const [ready, setReady] = useState(false);
    const reducedMotion = useMediaQuery("(prefers-reduced-motion: reduce)");
    const transitionDuration = reducedMotion ? 0 : 180;
    const photo = getPhoto(photoId)!;
    const thumbnailUrl = thumbnailUrls.get(photoId);

    useEffect(() => {
        let cancelled = false;
        let previewUrl: string | undefined;
        void getPreview(photoId)
            .then((blob) => {
                if (cancelled) return;
                if (blob) previewUrl = URL.createObjectURL(blob);
                setSource(previewUrl ?? thumbnailUrl);
            })
            .catch((error: unknown) => {
                if (cancelled) return;
                console.error("Failed to load photo preview", error);
                setSource(thumbnailUrl);
            });
        return () => {
            cancelled = true;
            if (previewUrl) URL.revokeObjectURL(previewUrl);
        };
    }, [photoId, thumbnailUrl]);

    useLayoutEffect(() => {
        const updateSize = () => {
            setSize({
                width: container.clientWidth,
                height: container.clientHeight,
            });
            void popperRef.current?.update();
        };
        updateSize();
        const observer = new ResizeObserver(updateSize);
        observer.observe(container);
        return () => observer.disconnect();
    }, [container]);

    return (
        <>
            <Portal>
                <Backdrop
                    open={ready}
                    transitionDuration={transitionDuration}
                    sx={{
                        bgcolor: "rgba(0, 0, 0, 0.7)",
                        zIndex: (theme) => theme.zIndex.tooltip - 1,
                        pointerEvents: "none",
                    }}
                />
            </Portal>
            <Popper
                open={!!source}
                popperRef={popperRef}
                placement="right"
                anchorEl={{
                    contextElement: anchor,
                    getBoundingClientRect: () => {
                        const rect = anchor.getBoundingClientRect();
                        return new DOMRect(
                            container.getBoundingClientRect().left,
                            rect.y,
                            0,
                            rect.height,
                        );
                    },
                }}
                modifiers={[
                    { name: "offset", options: { offset: [0, 16] } },
                    { name: "flip", enabled: false },
                    {
                        name: "preventOverflow",
                        options: {
                            boundary: container,
                            padding: 16,
                            altAxis: true,
                            tether: false,
                        },
                    },
                ]}
                sx={{
                    zIndex: (theme) => theme.zIndex.tooltip,
                    pointerEvents: "none",
                }}
            >
                <Fade in={ready} timeout={transitionDuration}>
                    <Box
                        component="img"
                        src={source}
                        alt={photo.fileName}
                        draggable={false}
                        onLoad={async () => {
                            await popperRef.current?.update();
                            setReady(true);
                        }}
                        sx={{
                            display: "block",
                            width: "auto",
                            height: "auto",
                            maxWidth: size.width - 32,
                            maxHeight: size.height - 32,
                            objectFit: "contain",
                            borderRadius: "12px",
                            bgcolor: toolbarColors.background,
                            boxShadow: popupShadow,
                        }}
                    />
                </Fade>
            </Popper>
        </>
    );
}
