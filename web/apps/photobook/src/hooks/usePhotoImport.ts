import { useBook } from "@/context/book";
import { getMaxAutoLayoutPhotos } from "@/lib/layouts";
import { MAX_PRINT_PAGES } from "@/lib/printProducts";
import { useRouter } from "next/router";
import {
    createContext,
    createElement,
    useCallback,
    useContext,
    useEffect,
    useRef,
    useState,
    type ReactNode,
} from "react";

const ACCEPTED_TYPES = [
    "image/jpeg",
    "image/png",
    "image/webp",
    "image/heic",
    "image/heif",
];

type EnteDialogStage = "closed" | "url" | "password";
type ImportSource = "album" | "files";
const maxPhotos = getMaxAutoLayoutPhotos(MAX_PRINT_PAGES);

function usePhotoImportSession() {
    const router = useRouter();
    const {
        addPhotos,
        addEntePhotos,
        processingPhotos,
        processingProgress,
        processingMessage,
        setAppView,
        loading,
    } = useBook(
        "addPhotos",
        "addEntePhotos",
        "processingPhotos",
        "processingProgress",
        "processingMessage",
        "setAppView",
        "loading",
    );
    const fileInputRef = useRef<HTMLInputElement>(null);
    const [dragOver, setDragOver] = useState(false);
    const [importError, setImportError] = useState<string | null>(null);
    const [importActive, setImportActive] = useState(false);
    const [importing, setImporting] = useState(false);
    const importingRef = useRef(false);
    const retryFilesRef = useRef<File[]>([]);
    const [oversizedImport, setOversizedImport] = useState<ImportSource | null>(
        null,
    );
    const limitResolverRef = useRef<((useFirst: boolean) => void) | null>(null);

    const [enteStage, setEnteStage] = useState<EnteDialogStage>("closed");
    const [enteUrl, setEnteUrl] = useState("");
    const [entePassword, setEntePassword] = useState("");
    const [enteError, setEnteError] = useState<string | null>(null);
    const passwordResolverRef = useRef<((pw: string | null) => void) | null>(
        null,
    );

    const beginImport = useCallback(() => {
        if (loading || importingRef.current) return false;
        importingRef.current = true;
        setImportActive(true);
        setImporting(true);
        setImportError(null);
        setEnteError(null);
        setEnteStage("closed");
        setAppView("edit");
        void router.push("/app");
        return true;
    }, [loading, router, setAppView]);

    const dismissImport = useCallback(() => {
        if (importingRef.current) return;
        setImportActive(false);
        setImportError(null);
        setEnteError(null);
        retryFilesRef.current = [];
    }, []);

    const openEnteDialog = useCallback(() => {
        setEnteStage("url");
        setEnteError(null);
        setEntePassword("");
    }, []);

    const closeEnteDialog = useCallback(() => {
        const resolve = passwordResolverRef.current;
        passwordResolverRef.current = null;
        if (resolve) resolve(null);
        setEnteStage("closed");
    }, []);

    const requestPassword = useCallback((): Promise<string | null> => {
        return new Promise((resolve) => {
            passwordResolverRef.current = resolve;
            setEntePassword("");
            setEnteError(null);
            setEnteStage("password");
        });
    }, []);

    const selectPhotos = useCallback(
        async <T>(photos: T[], source: ImportSource) => {
            if (photos.length <= maxPhotos) return photos;
            const useFirst = await new Promise<boolean>((resolve) => {
                limitResolverRef.current = resolve;
                setOversizedImport(source);
            });
            return useFirst ? photos.slice(0, maxPhotos) : null;
        },
        [],
    );

    const resolvePhotoLimit = (useFirst: boolean) => {
        limitResolverRef.current?.(useFirst);
        limitResolverRef.current = null;
        setOversizedImport(null);
    };

    const handleImportEnte = useCallback(async () => {
        const url = enteUrl.trim();
        if (!url) {
            setEnteError("Paste the album link first.");
            return;
        }
        if (!beginImport()) return;
        retryFilesRef.current = [];

        try {
            const { prepareEnteAlbum } = await import("@/lib/ente/import");
            const { credentials, files } = await prepareEnteAlbum(
                url,
                requestPassword,
            );
            if (!files.length)
                throw new Error("This album has no photos we can import.");
            const selected = await selectPhotos(files, "album");
            if (selected) {
                await addEntePhotos(credentials, selected);
                setEnteUrl("");
            }
            setImportActive(false);
        } catch (e) {
            const cancelled =
                (e as { cancelled?: boolean } | null)?.cancelled === true;
            if (cancelled) {
                setImportActive(false);
                return;
            }
            const msg =
                e instanceof Error ? e.message : "Something went wrong.";
            setEnteStage("url");
            setEnteError(msg);
        } finally {
            importingRef.current = false;
            setImporting(false);
        }
    }, [enteUrl, addEntePhotos, requestPassword, beginImport, selectPhotos]);

    const handleSubmitPassword = useCallback(() => {
        const resolve = passwordResolverRef.current;
        passwordResolverRef.current = null;
        setEnteStage("closed");
        if (resolve) resolve(entePassword);
    }, [entePassword]);

    const handleCancelPassword = useCallback(() => {
        const resolve = passwordResolverRef.current;
        passwordResolverRef.current = null;
        setEnteStage("closed");
        if (resolve) resolve(null);
    }, []);

    const handleFiles = useCallback(
        async (files: FileList | File[]) => {
            const valid = Array.from(files).filter((f) => {
                const ext = f.name.toLowerCase().split(".").pop();
                return (
                    ACCEPTED_TYPES.includes(f.type) ||
                    ext === "heic" ||
                    ext === "heif" ||
                    ext === "jpg" ||
                    ext === "jpeg" ||
                    ext === "png" ||
                    ext === "webp"
                );
            });

            if (valid.length > 0) {
                if (!beginImport()) return;
                try {
                    const selected = await selectPhotos(valid, "files");
                    if (selected) {
                        retryFilesRef.current = selected;
                        await addPhotos(selected, { replace: true });
                    }
                    retryFilesRef.current = [];
                    setImportActive(false);
                } catch (error) {
                    setImportError(
                        error instanceof Error
                            ? error.message
                            : "Couldn't import these photos. Please try again.",
                    );
                } finally {
                    importingRef.current = false;
                    setImporting(false);
                }
            }
        },
        [addPhotos, beginImport, selectPhotos],
    );

    const retryImport = useCallback(() => {
        if (retryFilesRef.current.length > 0)
            return handleFiles(retryFilesRef.current);
        return handleImportEnte();
    }, [handleFiles, handleImportEnte]);

    const handleDrop = useCallback(
        (e: React.DragEvent) => {
            e.preventDefault();
            setDragOver(false);
            void handleFiles(e.dataTransfer.files);
        },
        [handleFiles],
    );

    const handleDragOver = useCallback((e: React.DragEvent) => {
        e.preventDefault();
        setDragOver(true);
    }, []);

    const handleDragLeave = useCallback(() => {
        setDragOver(false);
    }, []);

    useEffect(
        () => () => {
            passwordResolverRef.current?.(null);
            passwordResolverRef.current = null;
            limitResolverRef.current?.(false);
            limitResolverRef.current = null;
        },
        [],
    );

    return {
        fileInputRef,
        maxPhotos,
        oversizedImport,
        resolvePhotoLimit,
        dragOver,
        enteStage,
        enteUrl,
        setEnteUrl,
        entePassword,
        setEntePassword,
        enteError,
        importError,
        processingPhotos,
        processingProgress: processingPhotos ? processingProgress : 0,
        processingMessage: processingPhotos
            ? processingMessage
            : "Preparing your photos...",
        openEnteDialog,
        closeEnteDialog,
        handleImportEnte,
        handleSubmitPassword,
        handleCancelPassword,
        handleFiles,
        handleDrop,
        handleDragOver,
        handleDragLeave,
        importActive,
        importing,
        dismissImport,
        retryImport,
    };
}

const PhotoImportContext = createContext<ReturnType<
    typeof usePhotoImportSession
> | null>(null);

export function PhotoImportProvider({ children }: { children: ReactNode }) {
    const session = usePhotoImportSession();
    return createElement(
        PhotoImportContext.Provider,
        { value: session },
        children,
    );
}

export function usePhotoImport() {
    const session = useContext(PhotoImportContext);
    if (!session)
        throw new Error(
            "usePhotoImport must be used within PhotoImportProvider",
        );
    return session;
}
