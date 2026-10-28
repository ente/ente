"use client";

import { useBook } from "@/context/book";
import { useRouter } from "next/navigation";
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

const MAX_PHOTOS = 800;

type EnteDialogStage = "closed" | "url" | "password";

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
    } = useBook();
    const fileInputRef = useRef<HTMLInputElement>(null);
    const [dragOver, setDragOver] = useState(false);
    const [importError, setImportError] = useState<string | null>(null);
    const [importActive, setImportActive] = useState(false);
    const [importing, setImporting] = useState(false);
    const importingRef = useRef(false);
    const retryFilesRef = useRef<File[]>([]);

    const [enteStage, setEnteStage] = useState<EnteDialogStage>("closed");
    const [enteUrl, setEnteUrl] = useState("");
    const [entePassword, setEntePassword] = useState("");
    const [enteError, setEnteError] = useState<string | null>(null);
    // Resolver for the password Promise handed back to addEntePhotos.
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
        router.push("/app");
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
        // If we're closing while waiting for a password, resolve with null so
        // the import aborts cleanly.
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

    const handleImportEnte = useCallback(async () => {
        const url = enteUrl.trim();
        if (!url) {
            setEnteError("Paste the album link first.");
            return;
        }
        if (!beginImport()) return;
        retryFilesRef.current = [];

        try {
            await addEntePhotos(url, requestPassword);
            setEnteUrl("");
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
            // Re-open the URL dialog with the error surfaced.
            setEnteStage("url");
            setEnteError(msg);
        } finally {
            importingRef.current = false;
            setImporting(false);
        }
    }, [enteUrl, addEntePhotos, requestPassword, beginImport]);

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
            const valid = Array.from(files)
                .filter((f) => {
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
                })
                .slice(0, MAX_PHOTOS);

            if (valid.length > 0) {
                if (!beginImport()) return;
                retryFilesRef.current = valid;
                try {
                    await addPhotos(valid, { replace: true });
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
        [addPhotos, beginImport],
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
        },
        [],
    );

    return {
        fileInputRef,
        dragOver,
        enteStage,
        enteUrl,
        setEnteUrl,
        entePassword,
        setEntePassword,
        enteError,
        importError,
        processingPhotos,
        processingProgress,
        processingMessage,
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

// The session outlives either route, including an outstanding album-password request.
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
