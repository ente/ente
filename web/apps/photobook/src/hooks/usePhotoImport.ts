import { useBook, useBookSelector } from "@/context/book";
import {
    albumImportIssue,
    type AlbumImportIssue,
} from "@/lib/ente/import-error";
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

type EnteDialogStage = "closed" | "url" | "password" | "replace";

interface AlbumImportOptions {
    linkDeviceToken?: string;
    confirmReplacement?: boolean;
}

function usePhotoImportSession() {
    const router = useRouter();
    const hasBook = useBookSelector((state) => state.book.pages.length > 0);
    const {
        addPhotos,
        addEntePhotos,
        processingPhotos,
        processingProgress,
        setAppView,
        loading,
    } = useBook(
        "addPhotos",
        "addEntePhotos",
        "processingPhotos",
        "processingProgress",
        "setAppView",
        "loading",
    );
    const fileInputRef = useRef<HTMLInputElement>(null);
    const [dragOver, setDragOver] = useState(false);
    const [importError, setImportError] = useState<string | null>(null);
    const [importActive, setImportActive] = useState(false);
    const [importCompleted, setImportCompleted] = useState(false);
    useEffect(() => {
        if (importCompleted && hasBook) setImportActive(false);
    }, [importCompleted, hasBook]);
    const clearImportCompleted = useCallback(
        () => setImportCompleted(false),
        [],
    );
    const [importing, setImporting] = useState(false);
    const importingRef = useRef(false);
    const retryFilesRef = useRef<File[]>([]);

    const [enteStage, setEnteStage] = useState<EnteDialogStage>("closed");
    const [enteUrl, setEnteUrl] = useState("");
    const [entePassword, setEntePassword] = useState("");
    const [enteError, setEnteError] = useState<AlbumImportIssue | null>(null);
    const [entePasswordError, setEntePasswordError] = useState<string>();
    const [verifyingPassword, setVerifyingPassword] = useState(false);
    const passwordResolverRef = useRef<((pw: string | null) => void) | null>(
        null,
    );
    const replacementResolverRef = useRef<((replace: boolean) => void) | null>(
        null,
    );
    const handoffRef = useRef<{
        url: string;
        options: AlbumImportOptions;
    } | null>(null);

    const beginImport = useCallback(() => {
        if (loading || importingRef.current) return false;
        importingRef.current = true;
        setImportActive(true);
        setImportCompleted(false);
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
        handoffRef.current = null;
    }, []);

    const chooseAnotherAlbum = useCallback(() => {
        setEnteUrl("");
        setEnteStage("url");
    }, []);

    const closeEnteDialog = useCallback(() => {
        setEnteUrl(handoffRef.current?.url ?? "");
        setEnteStage("closed");
    }, []);

    const requestPassword = useCallback(
        (error?: string): Promise<string | null> => {
            return new Promise((resolve) => {
                passwordResolverRef.current = resolve;
                if (!error) setEntePassword("");
                setEntePasswordError(error);
                setVerifyingPassword(false);
                setEnteError(null);
                setEnteStage("password");
            });
        },
        [],
    );

    const importEnteAlbum = useCallback(
        async (albumUrl: string, options: AlbumImportOptions = {}) => {
            const url = albumUrl.trim();
            if (!url) {
                setEnteError({
                    message: "Paste the album link first.",
                    canRetry: false,
                });
                return;
            }
            if (!beginImport()) return;
            setEnteUrl(url);
            handoffRef.current = { url, options };
            retryFilesRef.current = [];

            try {
                const { prepareEnteAlbum } = await import("@/lib/ente/import");
                const { credentials, files } = await prepareEnteAlbum(
                    url,
                    requestPassword,
                    options.linkDeviceToken,
                );
                setEnteStage("closed");
                setVerifyingPassword(false);
                if (!files.length)
                    throw new Error(
                        "This album has no photos we can import. Add photos to the album, then try again.",
                    );
                if (hasBook && options.confirmReplacement) {
                    const replace = await new Promise<boolean>((resolve) => {
                        replacementResolverRef.current = resolve;
                        setEnteStage("replace");
                    });
                    if (!replace) {
                        setImportActive(false);
                        handoffRef.current = null;
                        return;
                    }
                }
                await addEntePhotos(credentials, files);
                handoffRef.current = null;
                setEnteUrl("");
                setImportCompleted(true);
            } catch (e) {
                const cancelled =
                    (e as { cancelled?: boolean } | null)?.cancelled === true;
                if (cancelled) {
                    setImportActive(false);
                    return;
                }
                setEnteStage("closed");
                setEnteError(await albumImportIssue(e));
            } finally {
                setVerifyingPassword(false);
                importingRef.current = false;
                setImporting(false);
            }
        },
        [hasBook, addEntePhotos, requestPassword, beginImport],
    );

    const handleImportEnte = useCallback(
        () =>
            importEnteAlbum(
                enteUrl,
                handoffRef.current
                    ? {
                          ...handoffRef.current.options,
                          linkDeviceToken:
                              handoffRef.current.url === enteUrl.trim()
                                  ? handoffRef.current.options.linkDeviceToken
                                  : undefined,
                      }
                    : { confirmReplacement: true },
            ),
        [enteUrl, importEnteAlbum],
    );

    const handleReplaceBook = useCallback((replace: boolean) => {
        const resolve = replacementResolverRef.current;
        replacementResolverRef.current = null;
        setEnteStage("closed");
        resolve?.(replace);
    }, []);

    const handleSubmitPassword = useCallback(() => {
        const resolve = passwordResolverRef.current;
        if (!resolve) return;
        passwordResolverRef.current = null;
        setVerifyingPassword(true);
        setEntePasswordError(undefined);
        resolve(entePassword);
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
                retryFilesRef.current = valid;
                try {
                    await addPhotos(valid, { replace: true });
                    retryFilesRef.current = [];
                    setImportCompleted(true);
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
            replacementResolverRef.current?.(false);
            replacementResolverRef.current = null;
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
        entePasswordError,
        verifyingPassword,
        enteError,
        importError,
        processingPhotos,
        processingProgress: importCompleted
            ? 100
            : processingPhotos
              ? processingProgress
              : 0,
        closeEnteDialog,
        handleImportEnte,
        importEnteAlbum,
        handleReplaceBook,
        handleSubmitPassword,
        handleCancelPassword,
        handleFiles,
        handleDrop,
        handleDragOver,
        handleDragLeave,
        importActive,
        importCompleted,
        clearImportCompleted,
        importing: importing || (importActive && importCompleted),
        dismissImport,
        chooseAnotherAlbum,
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
