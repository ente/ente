import { consumePaste, setGuard, type PastePayload } from "@/services/paste";
import { useCallback, useEffect, useRef, useState } from "react";
import type { PageMode } from "../types";
import { waitUntilVisible } from "../utils/browser";
import {
    decryptConsumedPaste,
    IncorrectPastePasswordError,
    parsePasteKey,
    type PasteKey,
} from "../utils/pasteCrypto";

const errorMessage = (error: unknown) =>
    error instanceof Error ? error.message : "Paste is unavailable";

export const useConsumePaste = (mode: PageMode, accessToken: string | null) => {
    const [consuming, setConsuming] = useState(false);
    const [consumeError, setConsumeError] = useState<string | null>(null);
    const [resolvedText, setResolvedText] = useState<string | null>(null);
    const [passwordRequired, setPasswordRequired] = useState(false);
    const [passwordError, setPasswordError] = useState<string | null>(null);

    const consumeInFlightRef = useRef(false);
    const consumedPayloadRef = useRef<PastePayload | null>(null);
    const pasteKeyRef = useRef<PasteKey | null>(null);

    const confirmPasteAvailable = useCallback(async () => {
        if (!accessToken) return;

        try {
            setConsuming(true);
            setConsumeError(null);
            await waitUntilVisible();
            await setGuard(accessToken);
            setPasswordRequired(true);
        } catch (error) {
            setConsumeError(errorMessage(error));
        } finally {
            setConsuming(false);
        }
    }, [accessToken]);

    const consume = useCallback(
        async (pasteKey: PasteKey, password?: string) => {
            if (!accessToken || consumeInFlightRef.current) {
                return;
            }
            consumeInFlightRef.current = true;
            try {
                setConsuming(true);
                setConsumeError(null);
                setPasswordError(null);

                let payload = consumedPayloadRef.current;
                if (!payload) {
                    await waitUntilVisible();
                    await setGuard(accessToken);
                    payload = await consumePaste(accessToken);
                    consumedPayloadRef.current = payload;
                }

                setResolvedText(
                    await decryptConsumedPaste(pasteKey, payload, password),
                );
                setPasswordRequired(false);
            } catch (error) {
                if (error instanceof IncorrectPastePasswordError) {
                    setPasswordError(error.message);
                } else {
                    setConsumeError(errorMessage(error));
                }
            } finally {
                consumeInFlightRef.current = false;
                setConsuming(false);
            }
        },
        [accessToken],
    );

    useEffect(() => {
        if (mode !== "view" || !accessToken || pasteKeyRef.current) return;

        try {
            const fragment = window.location.hash.slice(1).trim();
            if (!fragment) {
                throw new Error("Missing key in URL");
            }

            const pasteKey = parsePasteKey(fragment);
            pasteKeyRef.current = pasteKey;
            if (pasteKey.passwordRequired) {
                void confirmPasteAvailable();
            } else {
                void consume(pasteKey);
            }
        } catch (error) {
            setConsumeError(errorMessage(error));
        }
    }, [mode, accessToken, confirmPasteAvailable, consume]);

    const submitPassword = async (password: string) => {
        if (!password) {
            setPasswordError("Enter the paste password");
            return;
        }
        if (!pasteKeyRef.current) {
            setConsumeError("Missing key in URL");
            return;
        }
        await consume(pasteKeyRef.current, password);
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
