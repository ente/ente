"use client";

import { BookContext } from "./book";

import {
    isBlankPage,
    isRequiredBlankPage,
    makeBlankPage,
    normalizeBookPages,
} from "@/lib/bookPages";
import {
    clearAll,
    getAppView,
    getBookState,
    getPhotos,
    getPreview,
    getThumbnail,
    saveAppView,
    saveBookState,
    savePhotoBlob,
    savePhotos,
    savePreview,
    saveThumbnail,
} from "@/lib/db";
import type { EnteCredentials, EnteFileDescriptor } from "@/lib/ente/types";
import { clearImageCache } from "@/lib/imageCache";
import {
    createThumbnail,
    extractExifDate,
    normalizeImportedImageBlob,
} from "@/lib/images";
import {
    applyVariant,
    chooseBestLayout,
    chooseBestVariantKey,
    generateAutoLayout,
    getVariantPreview,
    getVariantsForCount,
} from "@/lib/layouts";
import {
    availablePhotoSpaces,
    normalizeFrontCover,
    photoDestinationError,
    placeImportedPhotos,
    type AddPhotosOptions,
} from "@/lib/photoPlacement";
import { constrainTextBlock } from "@/lib/printLayout";
import type {
    AppView,
    BookPage,
    BookState,
    Photo,
    PhotoOriginalStatus,
    PhotoSlot,
    TextBlock,
} from "@/lib/types";
import React, {
    useCallback,
    useEffect,
    useMemo,
    useRef,
    useState,
} from "react";

const emptyBook: BookState = { pages: [], currentSpreadIndex: 0 };

function isPendingEnteOriginal(photo: Photo): boolean {
    return photo.source === "ente" && photo.originalStatus === "pending";
}

function pagePhotoIds(page: BookPage): string[] {
    return page.slots
        .map((s) => s.photoId)
        .filter((id): id is string => id !== null);
}

function normalizeCoverLayout(state: BookState): BookState {
    if (state.pages.length === 0) return state;
    let pages = normalizeFrontCover(state.pages);

    const cover = pages[0]!;
    const coverIds = pagePhotoIds(cover);
    const hasCoverLayout = getVariantsForCount(1, true).some(
        (variant) => variant.key === cover.layoutVariant,
    );
    if (coverIds.length === 1 && !hasCoverLayout) {
        pages = pages.map((p, i) =>
            i === 0
                ? {
                      ...p,
                      slots: cover.slots
                          .filter((slot) => slot.photoId)
                          .map((slot) => ({
                              ...slot,
                              ...getVariantPreview("1-full")[0],
                          })),
                      layoutVariant: "1-full",
                  }
                : p,
        );
    }

    pages = normalizeBookPages(pages);
    pages = pages.map((page) => {
        const textBlocks = page.textBlocks.map(constrainTextBlock);
        return textBlocks.some((block, i) => block !== page.textBlocks[i])
            ? { ...page, textBlocks }
            : page;
    });

    return pages === state.pages ? state : { ...state, pages };
}

function buildEnteOriginalDownloadJob(
    photo: Photo,
): { credentials: EnteCredentials; descriptor: EnteFileDescriptor } | null {
    const data = photo.enteOriginal;
    if (!data) return null;

    return {
        credentials: {
            apiOrigin: data.apiOrigin,
            albumsOrigin: data.albumsOrigin,
            accessToken: data.accessToken,
            accessTokenJWT: data.accessTokenJWT,
            collectionKey: "",
        },
        descriptor: {
            enteFileId: data.enteFileId,
            fileKey: data.fileKey,
            mediaKind: data.mediaKind,
            thumbnailDecryptionHeader: "",
            fileDecryptionHeader: data.fileDecryptionHeader,
            fileName: photo.fileName,
            dateTaken: photo.dateTaken,
            width: photo.width,
            height: photo.height,
        },
    };
}

export function BookProvider({ children }: { children: React.ReactNode }) {
    const [appView, setAppViewState] = useState<AppView>("edit");
    const [loading, setLoading] = useState(true);
    const [photos, setPhotos] = useState<Photo[]>([]);
    const photosRef = useRef<Photo[]>(photos);
    photosRef.current = photos;
    const [thumbnailUrls, setThumbnailUrls] = useState<Map<string, string>>(
        new Map(),
    );
    const thumbnailUrlsRef = useRef<Map<string, string>>(thumbnailUrls);
    thumbnailUrlsRef.current = thumbnailUrls;
    const [previewUrls, setPreviewUrls] = useState<Map<string, string>>(
        new Map(),
    );
    const previewUrlsRef = useRef<Map<string, string>>(previewUrls);
    previewUrlsRef.current = previewUrls;
    const [book, setBookRaw] = useState<BookState>(emptyBook);
    const [currentSpreadIndex, setCurrentSpreadIndex] = useState(0);
    const resettingRef = useRef(false);
    const isResetting = useCallback(() => resettingRef.current, []);
    const saveTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
    const autosaveRef = useRef<Promise<unknown>>(Promise.resolve());
    const originalWritesRef = useRef<Set<Promise<unknown>>>(new Set());

    // Revoke all object URLs on unmount to prevent memory leaks
    useEffect(() => {
        return () => {
            thumbnailUrlsRef.current.forEach((url) => URL.revokeObjectURL(url));
            previewUrlsRef.current.forEach((url) => URL.revokeObjectURL(url));
        };
    }, []);

    // Undo/Redo history
    const undoStackRef = useRef<BookState[]>([]);
    const redoStackRef = useRef<BookState[]>([]);
    const [canUndo, setCanUndo] = useState(false);
    const [canRedo, setCanRedo] = useState(false);
    const MAX_HISTORY = 50;

    const setBook: React.Dispatch<React.SetStateAction<BookState>> =
        useCallback((action) => {
            setBookRaw((prev) => {
                undoStackRef.current = [
                    ...undoStackRef.current.slice(-(MAX_HISTORY - 1)),
                    prev,
                ];
                redoStackRef.current = [];
                const next =
                    typeof action === "function" ? action(prev) : action;
                const pages = normalizeBookPages(
                    normalizeFrontCover(next.pages),
                );
                return pages === next.pages ? next : { ...next, pages };
            });
            setCanUndo(true);
            setCanRedo(false);
        }, []);

    const undo = useCallback(() => {
        if (undoStackRef.current.length === 0) return;
        setBookRaw((current) => {
            const prev = undoStackRef.current.pop()!;
            redoStackRef.current = [...redoStackRef.current, current];
            setCanUndo(undoStackRef.current.length > 0);
            setCanRedo(true);
            return normalizeCoverLayout(prev);
        });
    }, []);

    const redo = useCallback(() => {
        if (redoStackRef.current.length === 0) return;
        setBookRaw((current) => {
            const next = redoStackRef.current.pop()!;
            undoStackRef.current = [...undoStackRef.current, current];
            setCanUndo(true);
            setCanRedo(redoStackRef.current.length > 0);
            return normalizeCoverLayout(next);
        });
    }, []);
    // Merged URL map: preview (1080px) if loaded, else thumbnail (256px).
    // Consumers that need high-res (SpreadPage, BookViewer) use this + loadPreviews.
    // Consumers that only need tiny images (PageStrip) use thumbnailUrls directly.
    const photoUrls = useMemo(() => {
        if (previewUrls.size === 0) return thumbnailUrls;
        const merged = new Map(thumbnailUrls);
        for (const [id, url] of previewUrls) {
            merged.set(id, url);
        }
        return merged;
    }, [thumbnailUrls, previewUrls]);

    // Tracks which photo IDs are currently being loaded from IndexedDB to
    // prevent redundant concurrent reads when multiple components request
    // the same previews.
    const loadingPreviewsRef = useRef<Set<string>>(new Set());

    const loadPreviews = useCallback(async (photoIds: string[]) => {
        const missing = photoIds.filter(
            (id) =>
                !previewUrlsRef.current.has(id) &&
                !loadingPreviewsRef.current.has(id),
        );
        if (missing.length === 0) return;

        missing.forEach((id) => loadingPreviewsRef.current.add(id));

        const loaded = new Map<string, string>();
        await Promise.all(
            missing.map(async (id) => {
                try {
                    const blob = await getPreview(id);
                    if (blob) {
                        loaded.set(id, URL.createObjectURL(blob));
                    }
                } finally {
                    loadingPreviewsRef.current.delete(id);
                }
            }),
        );

        for (const [id, url] of loaded) {
            if (!photosRef.current.some((photo) => photo.id === id)) {
                URL.revokeObjectURL(url);
                loaded.delete(id);
            }
        }
        if (loaded.size > 0) {
            setPreviewUrls((prev) => {
                const next = new Map(prev);
                for (const [id, url] of loaded) next.set(id, url);
                return next;
            });
        }
    }, []);

    const [processingPhotos, setProcessingPhotos] = useState(false);
    const [processingProgress, setProcessingProgress] = useState(0);
    const [processingMessage, setProcessingMessage] = useState(
        "Processing your photos...",
    );
    const [importNotice, setImportNotice] = useState<string | null>(null);
    const clearImportNotice = useCallback(() => setImportNotice(null), []);
    const pendingEnteOriginals = useMemo(() => {
        const next = new Set<string>();
        for (const photo of photos) {
            if (isPendingEnteOriginal(photo)) {
                next.add(photo.id);
            }
        }
        return next;
    }, [photos]);
    const pendingEnteOriginalsRef = useRef<Set<string>>(pendingEnteOriginals);
    pendingEnteOriginalsRef.current = pendingEnteOriginals;
    const activeEnteOriginalDownloadsRef = useRef<Set<string>>(new Set());
    const enteOriginalWaitersRef = useRef<Map<string, (() => void)[]>>(
        new Map(),
    );
    // Persist on changes (debounced)
    useEffect(() => {
        if (loading || processingPhotos || resettingRef.current) return;
        const saveTimeout = setTimeout(() => {
            saveTimeoutRef.current = null;
            autosaveRef.current = autosaveRef.current
                .then(() =>
                    Promise.all([
                        saveBookState({ ...book, currentSpreadIndex }),
                        savePhotos(photos),
                        saveAppView(appView),
                    ]),
                )
                .catch((error: unknown) =>
                    console.error("Failed to save photobook", error),
                );
        }, 500);
        saveTimeoutRef.current = saveTimeout;

        return () => clearTimeout(saveTimeout);
    }, [book, photos, appView, currentSpreadIndex, loading, processingPhotos]);

    // Restore session on mount
    useEffect(() => {
        void (async () => {
            try {
                const [savedView, savedPhotos, savedBook] = await Promise.all([
                    getAppView(),
                    getPhotos(),
                    getBookState(),
                ]);

                if (savedBook?.pages.length === 0 && savedView === "edit") {
                    setBookRaw(emptyBook);
                    setAppViewState("edit");
                } else if (savedPhotos && savedPhotos.length > 0 && savedBook) {
                    await document.fonts.ready;
                    // Restore thumbnail URLs from IndexedDB (full-res loaded on demand for export)
                    const thumbUrls = new Map<string, string>();

                    await Promise.all(
                        savedPhotos.map(async (photo) => {
                            const thumb = await getThumbnail(photo.id);
                            if (thumb) {
                                thumbUrls.set(
                                    photo.id,
                                    URL.createObjectURL(thumb),
                                );
                            }
                        }),
                    );

                    // Ente photos left in "pending" state across sessions have stale
                    // credentials (tokens likely expired). Mark them as failed and strip
                    // the stored credentials so they don't linger in IndexedDB.
                    const restoredPhotos = savedPhotos.map((photo) =>
                        photo.source === "ente" &&
                        photo.originalStatus === "pending"
                            ? {
                                  ...photo,
                                  originalStatus: "failed" as const,
                                  enteOriginal: undefined,
                                  originalError:
                                      "Session expired — re-import the album to retry.",
                              }
                            : photo,
                    );

                    setPhotos(restoredPhotos);
                    setThumbnailUrls(thumbUrls);
                    setBookRaw(normalizeCoverLayout(savedBook));
                    setCurrentSpreadIndex(savedBook.currentSpreadIndex);

                    if (savedView === "edit" || savedView === "results") {
                        setAppViewState(savedView);
                    }
                }
            } catch (e) {
                console.error("Failed to restore session:", e);
            } finally {
                setLoading(false);
            }
        })();
    }, []);

    const setAppView = useCallback((view: AppView) => {
        setAppViewState(view);
    }, []);

    const progressRef = useRef(0);
    const rafRef = useRef<number>(0);

    const addPhotos = useCallback(
        async (files: File[], options: AddPhotosOptions = {}) => {
            const replace = options.replace ?? false;
            const destination = options.destination ?? { kind: "end" as const };
            if (!replace) {
                const error = photoDestinationError(
                    book.pages,
                    destination,
                    files.length,
                );
                if (error) throw new Error(error);
            }
            setProcessingPhotos(true);
            progressRef.current = 0;
            setProcessingProgress(0);
            setProcessingMessage("Processing your photos...");

            try {
                if (replace) {
                    // Clear previous session when starting fresh from start page
                    thumbnailUrls.forEach((url) => URL.revokeObjectURL(url));
                    previewUrls.forEach((url) => URL.revokeObjectURL(url));
                    clearImageCache();
                    await clearAll();
                }

                const newPhotos: Photo[] = [];
                const newThumbUrls = replace
                    ? new Map<string, string>()
                    : new Map(thumbnailUrls);
                const newPreviewUrls = replace
                    ? new Map<string, string>()
                    : new Map(previewUrls);

                // Flush progress to state only on animation frames
                const scheduleProgressUpdate = (value: number) => {
                    progressRef.current = value;
                    if (!rafRef.current) {
                        rafRef.current = requestAnimationFrame(() => {
                            rafRef.current = 0;
                            setProcessingProgress(progressRef.current);
                        });
                    }
                };

                // Process each photo: HEIC conversion, dimensions, thumbnail, IndexedDB save
                interface PhotoResult {
                    photo: Photo;
                    thumbUrl: string;
                    previewUrl: string;
                }
                const results: (PhotoResult | null)[] = Array.from(
                    { length: files.length },
                    () => null,
                );
                let completed = 0;

                const processPhoto = async (file: File, index: number) => {
                    try {
                        const blob = await normalizeImportedImageBlob(
                            file,
                            file.name,
                        );
                        const tempUrl = URL.createObjectURL(blob);
                        let img: HTMLImageElement;
                        try {
                            img = await loadImage(tempUrl);
                        } finally {
                            URL.revokeObjectURL(tempUrl);
                        }
                        const dateTaken = await extractExifDate(file);
                        const thumb = await createThumbnail(img, 256);
                        const preview = await createThumbnail(img, 1080);
                        const photo: Photo = {
                            id: crypto.randomUUID(),
                            fileName: file.name,
                            width: img.naturalWidth,
                            height: img.naturalHeight,
                            dateTaken:
                                dateTaken || file.lastModified || Date.now(),
                            source: "local",
                            originalStatus: "ready",
                        };
                        await savePhotoBlob(photo.id, blob);
                        await saveThumbnail(photo.id, thumb);
                        await savePreview(photo.id, preview);
                        results[index] = {
                            photo,
                            thumbUrl: URL.createObjectURL(thumb),
                            previewUrl: URL.createObjectURL(preview),
                        };
                    } catch (error) {
                        console.warn(
                            "Photo import failed for",
                            file.name,
                            error,
                        );
                    } finally {
                        completed++;
                        scheduleProgressUpdate(
                            Math.round((completed / files.length) * 100),
                        );
                    }
                };

                // Run with concurrency limit of 6
                const CONCURRENCY = 6;
                const taskQueue = files.map((f, i) => () => processPhoto(f, i));
                const workers = Array.from(
                    { length: Math.min(CONCURRENCY, files.length) },
                    async () => {
                        while (taskQueue.length > 0) {
                            const task = taskQueue.shift()!;
                            await task();
                        }
                    },
                );
                await Promise.all(workers);

                // Collect results in original file order
                for (const result of results) {
                    if (result) {
                        newThumbUrls.set(result.photo.id, result.thumbUrl);
                        newPreviewUrls.set(result.photo.id, result.previewUrl);
                        newPhotos.push(result.photo);
                    }
                }

                // Cancel any pending frame and flush final progress
                if (rafRef.current) {
                    cancelAnimationFrame(rafRef.current);
                    rafRef.current = 0;
                }
                setProcessingProgress(100);

                if (!replace && newPhotos.length === 0) {
                    throw new Error(
                        "These photos couldn't be read. Please choose different image files.",
                    );
                }
                const skipped = files.length - newPhotos.length;
                if (skipped > 0)
                    setImportNotice(
                        `${skipped} photo${skipped === 1 ? "" : "s"} couldn't be imported.`,
                    );

                const allPhotos = replace
                    ? newPhotos
                    : [...photos, ...newPhotos];
                const nextPages = replace
                    ? generateAutoLayout(allPhotos)
                    : placeImportedPhotos(
                          book.pages,
                          allPhotos,
                          newPhotos,
                          destination,
                      );
                const destinationIndex = replace
                    ? 0
                    : destination.kind === "page"
                      ? nextPages.findIndex(
                            (page) => page.id === destination.pageId,
                        )
                      : Math.max(0, book.pages.length - 1);
                setPhotos(allPhotos);
                setThumbnailUrls(newThumbUrls);
                setPreviewUrls(newPreviewUrls);

                if (replace) {
                    // Fresh session: generate auto layout from scratch (bypass undo tracking)
                    setBookRaw({ pages: nextPages, currentSpreadIndex: 0 });
                    undoStackRef.current = [];
                    redoStackRef.current = [];
                    setCanUndo(false);
                    setCanRedo(false);
                    setCurrentSpreadIndex(0);
                } else if (newPhotos.length > 0) {
                    setBook((prev) => ({ ...prev, pages: nextPages }));
                    setCurrentSpreadIndex(destinationIndex);
                }

                setAppViewState("edit");
                return nextPages[destinationIndex]?.id;
            } finally {
                if (rafRef.current) {
                    cancelAnimationFrame(rafRef.current);
                    rafRef.current = 0;
                }
                setProcessingPhotos(false);
            }
        },
        [book.pages, thumbnailUrls, previewUrls, photos, setBook],
    );

    const markEnteOriginalDone = useCallback(
        (
            photoId: string,
            status: PhotoOriginalStatus,
            originalError?: string,
        ) => {
            setPhotos((prev) =>
                prev.map((photo) => {
                    if (photo.id !== photoId || photo.source !== "ente") {
                        return photo;
                    }

                    const next: Photo = {
                        ...photo,
                        originalStatus: status,
                        originalError,
                    };
                    if (status === "ready" || status === "failed") {
                        next.enteOriginal = undefined;
                    }
                    return next;
                }),
            );
            const waiters = enteOriginalWaitersRef.current.get(photoId);
            if (waiters) {
                enteOriginalWaitersRef.current.delete(photoId);
                for (const w of waiters) w();
            }
        },
        [],
    );

    const startEnteOriginalDownloads = useCallback(
        async (photoIds: string[]) => {
            const entries = photoIds
                .map((photoId) => {
                    const photo = photosRef.current.find(
                        (candidate) => candidate.id === photoId,
                    );
                    if (!photo || !isPendingEnteOriginal(photo)) {
                        return null;
                    }
                    const job = buildEnteOriginalDownloadJob(photo);
                    if (!job) {
                        markEnteOriginalDone(
                            photoId,
                            "failed",
                            "Missing Ente download metadata.",
                        );
                        return null;
                    }
                    return { photoId, fileName: photo.fileName, ...job };
                })
                .filter(
                    (
                        entry,
                    ): entry is {
                        photoId: string;
                        fileName: string;
                        credentials: EnteCredentials;
                        descriptor: EnteFileDescriptor;
                    } => entry !== null,
                );

            // Ente's CDN tolerates a few parallel requests; match Ente web's default.
            const CONCURRENCY = 3;
            let cursor = 0;
            const workers = Array.from(
                { length: Math.min(CONCURRENCY, entries.length) },
                async () => {
                    while (cursor < entries.length) {
                        const i = cursor++;
                        const { photoId, fileName, credentials, descriptor } =
                            entries[i]!;
                        try {
                            if (
                                isResetting() ||
                                !photosRef.current.some(
                                    (photo) => photo.id === photoId,
                                )
                            )
                                continue;
                            const {
                                fetchAndDecryptOriginal,
                                extractRenderableImage,
                            } = await import("@/lib/ente/import");
                            const blob = await fetchAndDecryptOriginal(
                                credentials,
                                descriptor,
                            );
                            const renderable = await extractRenderableImage(
                                descriptor,
                                blob,
                            );
                            const normalizedBlob =
                                await normalizeImportedImageBlob(
                                    renderable.blob,
                                    renderable.fileName,
                                );
                            const normalizedUrl =
                                URL.createObjectURL(normalizedBlob);
                            let previewBlob: Blob;
                            try {
                                const img = await loadImage(normalizedUrl);
                                previewBlob = await createThumbnail(img, 1080);
                            } finally {
                                URL.revokeObjectURL(normalizedUrl);
                            }
                            const currentPhoto = photosRef.current.find(
                                (candidate) => candidate.id === photoId,
                            );
                            if (
                                isResetting() ||
                                !currentPhoto ||
                                !isPendingEnteOriginal(currentPhoto)
                            ) {
                                continue;
                            }
                            const write = Promise.all([
                                savePhotoBlob(photoId, normalizedBlob),
                                savePreview(photoId, previewBlob),
                            ]);
                            originalWritesRef.current.add(write);
                            try {
                                await write;
                            } finally {
                                originalWritesRef.current.delete(write);
                            }
                            if (
                                isResetting() ||
                                !photosRef.current.some(
                                    (photo) => photo.id === photoId,
                                )
                            )
                                continue;
                            const previewUrl = URL.createObjectURL(previewBlob);
                            setPreviewUrls((prev) => {
                                const next = new Map(prev);
                                const existing = next.get(photoId);
                                if (existing) {
                                    URL.revokeObjectURL(existing);
                                }
                                next.set(photoId, previewUrl);
                                return next;
                            });
                            markEnteOriginalDone(photoId, "ready");
                        } catch (e) {
                            const currentPhoto = photosRef.current.find(
                                (candidate) => candidate.id === photoId,
                            );
                            if (
                                !resettingRef.current &&
                                currentPhoto &&
                                isPendingEnteOriginal(currentPhoto)
                            ) {
                                const message =
                                    e instanceof Error
                                        ? e.message
                                        : "Failed to prepare the original photo.";
                                console.warn(
                                    `Ente: failed to download original for "${fileName}"`,
                                    e,
                                );
                                markEnteOriginalDone(
                                    photoId,
                                    "failed",
                                    message,
                                );
                            }
                        } finally {
                            activeEnteOriginalDownloadsRef.current.delete(
                                photoId,
                            );
                        }
                    }
                },
            );
            await Promise.all(workers);
        },
        [markEnteOriginalDone, isResetting],
    );

    const addEntePhotos = useCallback(
        async (
            albumUrl: string,
            requestPassword: () => Promise<string | null>,
        ) => {
            setProcessingPhotos(true);
            progressRef.current = 0;
            setProcessingProgress(0);
            setProcessingMessage("Importing your photos...");

            let preparation;
            let fetchAndDecryptThumbnail: (typeof import("@/lib/ente/import"))["fetchAndDecryptThumbnail"];
            try {
                // Keep loading visible while browser-only cryptography is fetched.
                const enteImport = await import("@/lib/ente/import");
                fetchAndDecryptThumbnail = enteImport.fetchAndDecryptThumbnail;
                preparation = await enteImport.prepareEnteAlbum(
                    albumUrl,
                    requestPassword,
                );
                if (preparation.files.length === 0)
                    throw new Error("This album has no photos we can import.");

                // A bad link or a cancelled password prompt must leave the existing book intact.
                thumbnailUrlsRef.current.forEach((url) =>
                    URL.revokeObjectURL(url),
                );
                previewUrlsRef.current.forEach((url) =>
                    URL.revokeObjectURL(url),
                );
                clearImageCache();
                await clearAll();
                activeEnteOriginalDownloadsRef.current.clear();
                enteOriginalWaitersRef.current = new Map();
            } catch (e) {
                setProcessingPhotos(false);
                setProcessingMessage("Processing your photos...");
                throw e;
            }

            const { credentials, files } = preparation;
            const MAX_PHOTOS = 800;
            const limited = files.slice(0, MAX_PHOTOS);
            if (files.length > MAX_PHOTOS) {
                setImportNotice(
                    `This album has ${files.length} photos. We imported the first ${MAX_PHOTOS}.`,
                );
            }

            // Keep the same message throughout.

            interface ThumbResult {
                photo: Photo;
                thumbUrl: string;
                previewUrl: string;
            }
            const thumbResults: (ThumbResult | null)[] = Array.from(
                { length: limited.length },
                () => null,
            );
            let completed = 0;

            const scheduleProgressUpdate = (value: number) => {
                progressRef.current = value;
                if (!rafRef.current) {
                    rafRef.current = requestAnimationFrame(() => {
                        rafRef.current = 0;
                        setProcessingProgress(progressRef.current);
                    });
                }
            };

            const processOne = async (index: number) => {
                const descriptor = limited[index]!;
                try {
                    const thumbBlob = await fetchAndDecryptThumbnail(
                        credentials,
                        descriptor,
                    );

                    // Trust magic-metadata dimensions if present; otherwise fall back to
                    // the thumbnail's own dimensions. The thumbnail preserves aspect
                    // ratio, so that's enough for the photobook's auto-layout picker.
                    let width = descriptor.width;
                    let height = descriptor.height;
                    if (!width || !height) {
                        const tempUrl = URL.createObjectURL(thumbBlob);
                        try {
                            const img = await loadImage(tempUrl);
                            width = img.naturalWidth;
                            height = img.naturalHeight;
                        } finally {
                            URL.revokeObjectURL(tempUrl);
                        }
                    }

                    const photoId = crypto.randomUUID();
                    const photo: Photo = {
                        id: photoId,
                        fileName: descriptor.fileName,
                        width,
                        height,
                        dateTaken: descriptor.dateTaken,
                        source: "ente",
                        originalStatus: "pending",
                        enteOriginal: {
                            apiOrigin: credentials.apiOrigin,
                            albumsOrigin: credentials.albumsOrigin,
                            accessToken: credentials.accessToken,
                            accessTokenJWT: credentials.accessTokenJWT,
                            enteFileId: descriptor.enteFileId,
                            mediaKind: descriptor.mediaKind,
                            fileKey: descriptor.fileKey,
                            fileDecryptionHeader:
                                descriptor.fileDecryptionHeader,
                        },
                    };

                    // Save the decrypted thumbnail for immediate rendering. The original
                    // blob is written later once the background download succeeds.
                    await Promise.all([
                        saveThumbnail(photoId, thumbBlob),
                        savePreview(photoId, thumbBlob),
                    ]);

                    thumbResults[index] = {
                        photo,
                        thumbUrl: URL.createObjectURL(thumbBlob),
                        previewUrl: URL.createObjectURL(thumbBlob),
                    };
                } catch (e) {
                    console.warn(
                        `Ente: failed to prepare "${descriptor.fileName}"`,
                        e,
                    );
                } finally {
                    completed++;
                    scheduleProgressUpdate(
                        Math.round((completed / limited.length) * 100),
                    );
                }
            };

            const THUMB_CONCURRENCY = 6;
            let cursor = 0;
            const workers = Array.from(
                { length: Math.min(THUMB_CONCURRENCY, limited.length) },
                async () => {
                    while (cursor < limited.length) {
                        const i = cursor++;
                        await processOne(i);
                    }
                },
            );
            await Promise.all(workers);

            if (rafRef.current) {
                cancelAnimationFrame(rafRef.current);
                rafRef.current = 0;
            }
            setProcessingProgress(100);

            const successful = thumbResults.filter(
                (r): r is ThumbResult => r !== null,
            );
            successful.sort((a, b) => a.photo.dateTaken - b.photo.dateTaken);

            if (successful.length === 0) {
                setProcessingPhotos(false);
                setProcessingMessage("Processing your photos...");
                throw new Error(
                    "We couldn't prepare any photos from this album.",
                );
            }

            const newPhotos: Photo[] = successful.map((r) => r.photo);
            const newThumbUrls = new Map<string, string>();
            const newPreviewUrls = new Map<string, string>();
            for (const r of successful) {
                newThumbUrls.set(r.photo.id, r.thumbUrl);
                newPreviewUrls.set(r.photo.id, r.previewUrl);
            }

            const pages = generateAutoLayout(newPhotos);
            setPhotos(newPhotos);
            setThumbnailUrls(newThumbUrls);
            setPreviewUrls(newPreviewUrls);
            setBookRaw({ pages, currentSpreadIndex: 0 });
            undoStackRef.current = [];
            redoStackRef.current = [];
            setCanUndo(false);
            setCanRedo(false);
            setCurrentSpreadIndex(0);

            setProcessingPhotos(false);
            setProcessingMessage("Processing your photos...");
            setAppViewState("edit");
        },
        [],
    );

    const waitForEnteOriginals = useCallback(
        async (
            photoIds?: string[],
            onProgress?: (done: number, total: number) => void,
        ) => {
            const requested =
                photoIds ?? Array.from(pendingEnteOriginalsRef.current);
            const pending = requested.filter((id) =>
                pendingEnteOriginalsRef.current.has(id),
            );
            if (pending.length === 0) return;
            const total = pending.length;
            let done = 0;
            onProgress?.(done, total);
            await Promise.all(
                pending.map(
                    (id) =>
                        new Promise<void>((resolve) => {
                            // If it already resolved between the snapshot and now, short-circuit.
                            if (!pendingEnteOriginalsRef.current.has(id)) {
                                done++;
                                onProgress?.(done, total);
                                resolve();
                                return;
                            }
                            const existing =
                                enteOriginalWaitersRef.current.get(id) ?? [];
                            existing.push(() => {
                                done++;
                                onProgress?.(done, total);
                                resolve();
                            });
                            enteOriginalWaitersRef.current.set(id, existing);
                        }),
                ),
            );
        },
        [],
    );

    useEffect(() => {
        if (loading || processingPhotos) return;

        const queue = photos
            .filter(
                (photo) =>
                    isPendingEnteOriginal(photo) &&
                    !activeEnteOriginalDownloadsRef.current.has(photo.id),
            )
            .map((photo) => photo.id);

        if (queue.length === 0) return;

        queue.forEach((photoId) =>
            activeEnteOriginalDownloadsRef.current.add(photoId),
        );
        void startEnteOriginalDownloads(queue);
    }, [loading, photos, processingPhotos, startEnteOriginalDownloads]);

    const addPage = useCallback(
        (afterIndex?: number) => {
            const newPage = makeBlankPage();
            setBook((prev) => {
                const pages = [...prev.pages];
                const lastIndex = pages.length - 1;
                const requestedIndex =
                    afterIndex !== undefined ? afterIndex + 1 : lastIndex;
                const idx =
                    pages.length > 1
                        ? Math.max(1, Math.min(requestedIndex, lastIndex))
                        : pages.length;
                pages.splice(idx, 0, newPage);
                return { ...prev, pages };
            });
            return newPage.id;
        },
        [setBook],
    );

    const removePage = useCallback(
        (pageId: string) => {
            setBook((prev) => {
                if (
                    pageId === prev.pages[0]?.id ||
                    pageId === prev.pages.at(-1)?.id
                )
                    return prev;
                if (isRequiredBlankPage(prev.pages, pageId)) return prev;
                const filtered = prev.pages.filter((p) => p.id !== pageId);
                // Prevent deleting below 2 pages
                if (filtered.length < 2) return prev;
                // Ensure even page count for spreads
                if (filtered.length % 2 !== 0) {
                    // Remove another blank interior page if possible; otherwise pad before
                    // the existing back cover so its identity and position stay intact.
                    const blankIdx = filtered.findIndex(
                        (p, i) =>
                            i > 0 && i < filtered.length - 1 && isBlankPage(p),
                    );
                    if (blankIdx !== -1 && filtered.length - 1 >= 2) {
                        filtered.splice(blankIdx, 1);
                    } else {
                        filtered.splice(
                            filtered.length - 1,
                            0,
                            makeBlankPage(),
                        );
                    }
                }
                return { ...prev, pages: filtered };
            });
        },
        [setBook],
    );

    const reorderPages = useCallback(
        (fromIndex: number, toIndex: number) => {
            setBook((prev) => {
                const lastIndex = prev.pages.length - 1;
                if (
                    fromIndex <= 0 ||
                    fromIndex >= lastIndex ||
                    toIndex <= 0 ||
                    toIndex >= lastIndex
                )
                    return prev;
                const pages = [...prev.pages];
                const [moved] = pages.splice(fromIndex, 1);
                pages.splice(toIndex, 0, moved!);
                return { ...prev, pages };
            });
        },
        [setBook],
    );

    const updatePage = useCallback(
        (pageId: string, updates: Partial<BookPage>) => {
            setBook((prev) => ({
                ...prev,
                pages: prev.pages.map((p) =>
                    p.id === pageId ? { ...p, ...updates } : p,
                ),
            }));
        },
        [setBook],
    );

    const updateSlot = useCallback(
        (pageId: string, slotId: string, updates: Partial<PhotoSlot>) => {
            setBook((prev) => ({
                ...prev,
                pages: prev.pages.map((p) =>
                    p.id === pageId
                        ? {
                              ...p,
                              slots: p.slots.map((s) =>
                                  s.id === slotId ? { ...s, ...updates } : s,
                              ),
                          }
                        : p,
                ),
            }));
        },
        [setBook],
    );

    const removeSlot = useCallback(
        (pageId: string, slotId: string) => {
            setBook((prev) => {
                const page = prev.pages.find((p) => p.id === pageId);
                if (!page) return prev;

                const remainingPhotos = page.slots
                    .filter((s) => s.id !== slotId && s.photoId)
                    .map((s) => s.photoId!);

                if (remainingPhotos.length === 0) {
                    return {
                        ...prev,
                        pages: prev.pages.map((p) =>
                            p.id === pageId
                                ? { ...p, slots: [], layoutVariant: undefined }
                                : p,
                        ),
                    };
                }

                const isCoverPage = prev.pages[0]?.id === pageId;
                // A front cover reduced to one photo defaults to full-bleed.
                let variantKey: string | undefined;
                if (remainingPhotos.length === 1 && isCoverPage) {
                    variantKey = "1-full";
                } else {
                    variantKey = getVariantsForCount(remainingPhotos.length)[0]
                        ?.key;
                }
                if (!variantKey) {
                    return {
                        ...prev,
                        pages: prev.pages.map((p) =>
                            p.id === pageId
                                ? {
                                      ...p,
                                      slots: p.slots.filter(
                                          (s) => s.id !== slotId,
                                      ),
                                  }
                                : p,
                        ),
                    };
                }

                const newSlots = applyVariant(variantKey, remainingPhotos);

                return {
                    ...prev,
                    pages: prev.pages.map((p) =>
                        p.id === pageId
                            ? {
                                  ...p,
                                  slots: newSlots,
                                  layoutVariant: variantKey,
                              }
                            : p,
                    ),
                };
            });
        },
        [setBook],
    );

    const swapPhotos = useCallback(
        (
            fromPageId: string,
            fromSlotId: string,
            toPageId: string,
            toSlotId: string,
        ) => {
            setBook((prev) => {
                if (
                    toPageId === prev.pages.at(-1)?.id ||
                    fromPageId === prev.pages.at(-1)?.id
                )
                    return prev;
                const pages = prev.pages.map((p) => ({
                    ...p,
                    slots: p.slots.map((s) => {
                        if (p.id === fromPageId && s.id === fromSlotId) {
                            return { ...s };
                        }
                        if (p.id === toPageId && s.id === toSlotId) {
                            return { ...s };
                        }
                        return s;
                    }),
                }));

                let fromSlot: PhotoSlot | undefined;
                let toSlot: PhotoSlot | undefined;

                for (const page of pages) {
                    for (const slot of page.slots) {
                        if (page.id === fromPageId && slot.id === fromSlotId)
                            fromSlot = slot;
                        if (page.id === toPageId && slot.id === toSlotId)
                            toSlot = slot;
                    }
                }

                if (fromSlot && toSlot) {
                    const tempPhotoId = fromSlot.photoId;
                    fromSlot.photoId = toSlot.photoId;
                    toSlot.photoId = tempPhotoId;
                }

                return { ...prev, pages };
            });
        },
        [setBook],
    );

    const movePhotoToPage = useCallback(
        (fromPageId: string, fromSlotId: string, toPageId: string) => {
            setBook((prev) => {
                if (toPageId === prev.pages.at(-1)?.id) return prev;
                const fromPage = prev.pages.find((p) => p.id === fromPageId);
                const toPage = prev.pages.find((p) => p.id === toPageId);
                if (!fromPage || !toPage || fromPageId === toPageId)
                    return prev;
                if (
                    availablePhotoSpaces(
                        toPage,
                        prev.pages[0]?.id === toPageId,
                    ) === 0
                )
                    return prev;

                const fromSlot = fromPage.slots.find(
                    (s) => s.id === fromSlotId,
                );
                if (!fromSlot?.photoId) return prev;

                const movedPhotoId = fromSlot.photoId;

                // Collect photoIds for each page after the move
                const sourcePhotoIds = fromPage.slots
                    .map((s) => s.photoId)
                    .filter(
                        (id): id is string =>
                            id !== null && id !== movedPhotoId,
                    );
                const targetPhotoIds = [
                    ...toPage.slots
                        .map((s) => s.photoId)
                        .filter((id): id is string => id !== null),
                    movedPhotoId,
                ];

                if (targetPhotoIds.length > 4) return prev;

                // Build fake Photo objects for chooseBestLayout (it needs width/height for orientation)
                const makePhotoStub = (photoId: string): Photo => {
                    const photo = photos.find((p) => p.id === photoId);
                    return (
                        photo || {
                            id: photoId,
                            fileName: "",
                            width: 1,
                            height: 1,
                            dateTaken: 0,
                        }
                    );
                };

                const newPages = prev.pages.map((p, pIdx) => {
                    const isCover = pIdx === 0;
                    const coverSingleKey = isCover ? "1-full" : null;
                    if (p.id === fromPageId) {
                        if (sourcePhotoIds.length === 0) {
                            return {
                                ...p,
                                slots: [],
                                layoutVariant: undefined,
                            };
                        }
                        if (coverSingleKey && sourcePhotoIds.length === 1) {
                            return {
                                ...p,
                                slots: applyVariant(
                                    coverSingleKey,
                                    sourcePhotoIds,
                                ),
                                layoutVariant: coverSingleKey,
                            };
                        }
                        const srcPhotos = sourcePhotoIds.map(makePhotoStub);
                        return {
                            ...p,
                            slots: chooseBestLayout(srcPhotos),
                            layoutVariant: chooseBestVariantKey(srcPhotos),
                        };
                    }
                    if (p.id === toPageId) {
                        if (coverSingleKey && targetPhotoIds.length === 1) {
                            return {
                                ...p,
                                slots: applyVariant(
                                    coverSingleKey,
                                    targetPhotoIds,
                                ),
                                layoutVariant: coverSingleKey,
                            };
                        }
                        const tgtPhotos = targetPhotoIds.map(makePhotoStub);
                        return {
                            ...p,
                            slots: chooseBestLayout(tgtPhotos),
                            layoutVariant: chooseBestVariantKey(tgtPhotos),
                        };
                    }
                    return p;
                });

                return { ...prev, pages: newPages };
            });
        },
        [photos, setBook],
    );

    const setPageLayout = useCallback(
        (pageId: string, variantKey: string) => {
            setBook((prev) => {
                if (pageId === prev.pages.at(-1)?.id) return prev;
                const page = prev.pages.find((p) => p.id === pageId);
                if (!page) return prev;
                const photoIds = page.slots
                    .map((s) => s.photoId)
                    .filter((id): id is string => id !== null);
                if (
                    pageId === prev.pages[0]?.id &&
                    getVariantPreview(variantKey).length !== 1
                )
                    return prev;
                const newSlots = applyVariant(variantKey, photoIds);
                if (newSlots.length === 0) return prev;
                return {
                    ...prev,
                    pages: prev.pages.map((p) =>
                        p.id === pageId
                            ? {
                                  ...p,
                                  slots: newSlots,
                                  layoutVariant: variantKey,
                              }
                            : p,
                    ),
                };
            });
        },
        [setBook],
    );

    const addTextBlock = useCallback(
        (pageId: string): TextBlock => {
            const block: TextBlock = constrainTextBlock({
                id: crypto.randomUUID(),
                text: "",
                x: 50,
                y: 40,
                width: 45,
                height: 15,
                style: "body",
                alignment: "right",
                color: "#555555",
                rotation: 0,
                fontSize: 2.5,
            });
            setBook((prev) => ({
                ...prev,
                pages: prev.pages.map((p) =>
                    p.id === pageId
                        ? { ...p, textBlocks: [...p.textBlocks, block] }
                        : p,
                ),
            }));
            return block;
        },
        [setBook],
    );

    const updateTextBlock = useCallback(
        (pageId: string, blockId: string, updates: Partial<TextBlock>) => {
            setBook((prev) => ({
                ...prev,
                pages: prev.pages.map((p) =>
                    p.id === pageId
                        ? {
                              ...p,
                              textBlocks: p.textBlocks.map((t) =>
                                  t.id === blockId
                                      ? constrainTextBlock({ ...t, ...updates })
                                      : t,
                              ),
                          }
                        : p,
                ),
            }));
        },
        [setBook],
    );

    const removeTextBlock = useCallback(
        (pageId: string, blockId: string) => {
            setBook((prev) => ({
                ...prev,
                pages: prev.pages.map((p) =>
                    p.id === pageId
                        ? {
                              ...p,
                              textBlocks: p.textBlocks.filter(
                                  (t) => t.id !== blockId,
                              ),
                          }
                        : p,
                ),
            }));
        },
        [setBook],
    );

    const startOver = useCallback(async () => {
        resettingRef.current = true;
        if (saveTimeoutRef.current !== null)
            clearTimeout(saveTimeoutRef.current);
        saveTimeoutRef.current = null;
        try {
            // Finish writes already in flight before clearing the browser's book.
            await Promise.allSettled([
                autosaveRef.current,
                ...originalWritesRef.current,
            ]);
            await clearAll();
            thumbnailUrlsRef.current.forEach((url) => URL.revokeObjectURL(url));
            previewUrlsRef.current.forEach((url) => URL.revokeObjectURL(url));
            clearImageCache();

            photosRef.current = [];
            pendingEnteOriginalsRef.current = new Set();
            setPhotos([]);
            setThumbnailUrls(new Map());
            setPreviewUrls(new Map());
            setBookRaw(emptyBook);
            undoStackRef.current = [];
            redoStackRef.current = [];
            setCanUndo(false);
            setCanRedo(false);
            setCurrentSpreadIndex(0);
            setImportNotice(null);
            setAppViewState("edit");
            activeEnteOriginalDownloadsRef.current.clear();
            enteOriginalWaitersRef.current.forEach((waiters) =>
                waiters.forEach((resolve) => resolve()),
            );
            enteOriginalWaitersRef.current = new Map();
        } catch (error) {
            setPhotos((current) => [...current]);
            throw error;
        } finally {
            resettingRef.current = false;
        }
    }, []);

    return (
        <BookContext.Provider
            value={{
                appView,
                setAppView,
                loading,
                photos,
                thumbnailUrls,
                photoUrls,
                loadPreviews,
                addPhotos,
                addEntePhotos,
                processingPhotos,
                processingProgress,
                processingMessage,
                importNotice,
                clearImportNotice,
                pendingEnteOriginals,
                waitForEnteOriginals,
                book,
                setBook,
                currentSpreadIndex,
                setCurrentSpreadIndex,
                addPage,
                removePage,
                reorderPages,
                updatePage,
                updateSlot,
                removeSlot,
                swapPhotos,
                movePhotoToPage,
                setPageLayout,
                addTextBlock,
                updateTextBlock,
                removeTextBlock,
                undo,
                redo,
                canUndo,
                canRedo,
                startOver,
            }}
        >
            {children}
        </BookContext.Provider>
    );
}

function loadImage(src: string): Promise<HTMLImageElement> {
    return new Promise((resolve, reject) => {
        const img = new Image();
        img.onload = () => resolve(img);
        img.onerror = reject;
        img.src = src;
    });
}
