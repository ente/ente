import { waitUntilVisible } from "@/browser";
import {
    consumePasteErrorMessage,
    createPasteErrorMessage,
    pasteClient,
} from "@/paste";
import { useEffect, useRef, useState } from "react";

export const usePasteRoute = () => {
    const [mode, setMode] = useState<"create" | "view">("create");

    useEffect(() => {
        const cleanPath = window.location.pathname.replace(/^\/+|\/+$/g, "");
        setMode(cleanPath ? "view" : "create");
    }, []);

    return mode;
};

export const useCreatePaste = () => {
    const [inputText, setInputText] = useState("");
    const [creating, setCreating] = useState(false);
    const [createError, setCreateError] = useState<string | null>(null);
    const [createdLink, setCreatedLink] = useState<string | null>(null);
    const [createdLinkPasswordProtected, setCreatedLinkPasswordProtected] =
        useState(false);

    const createSecureLink = async (password?: string) => {
        setCreating(true);
        setCreateError(null);
        try {
            const paste = await (
                await pasteClient()
            ).create(window.location.origin, inputText, password);
            setCreatedLink(paste.url);
            setCreatedLinkPasswordProtected(paste.passwordRequired);
        } catch (error) {
            setCreateError(createPasteErrorMessage(error));
        } finally {
            setCreating(false);
        }
    };

    return {
        inputText,
        setInputText,
        creating,
        createError,
        createdLink,
        createdLinkPasswordProtected,
        createSecureLink,
    };
};

export const useConsumePaste = () => {
    const [consuming, setConsuming] = useState(false);
    const [consumeError, setConsumeError] = useState<string | null>(null);
    const [resolvedText, setResolvedText] = useState<string | null>(null);
    const [passwordRequired, setPasswordRequired] = useState(false);
    const [passwordError, setPasswordError] = useState<string | null>(null);
    const openStartedRef = useRef(false);
    const consumeInFlightRef = useRef(false);

    useEffect(() => {
        if (openStartedRef.current) return;
        openStartedRef.current = true;

        const open = async () => {
            setConsuming(true);
            setConsumeError(null);
            try {
                await waitUntilVisible();
                const paste = await (
                    await pasteClient()
                ).open(window.location.href);
                if (paste.passwordRequired) {
                    setPasswordRequired(true);
                } else {
                    setResolvedText(paste.text);
                }
            } catch (error) {
                setConsumeError(consumePasteErrorMessage(error));
            } finally {
                setConsuming(false);
            }
        };

        void open();
    }, []);

    const submitPassword = async (password: string) => {
        if (!password) {
            setPasswordError("Enter the paste password");
            return;
        }
        if (consumeInFlightRef.current) return;
        consumeInFlightRef.current = true;
        setConsuming(true);
        setConsumeError(null);
        setPasswordError(null);
        try {
            setResolvedText(
                await (await pasteClient()).submitPassword(password),
            );
            setPasswordRequired(false);
        } catch (error) {
            const code = error instanceof Error ? error.name : undefined;
            if (code === "incorrect_password") {
                setPasswordError("Incorrect paste password");
            } else if (code === "password_required") {
                setPasswordError("Enter the paste password");
            } else {
                setConsumeError(consumePasteErrorMessage(error));
            }
        } finally {
            consumeInFlightRef.current = false;
            setConsuming(false);
        }
    };

    return {
        consuming,
        consumeError,
        resolvedText,
        passwordRequired,
        passwordError,
        submitPassword,
    };
};
