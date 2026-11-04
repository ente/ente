import { abortable } from "@/services/abortable";
import {
    DesktopDictation,
    insertVoiceText,
    voiceTransport,
    type VoiceAnchor,
    type VoiceOutcome,
} from "@/services/voice";
import log from "ente-base/log";
import { useCallback, useEffect, useRef, useState } from "react";

export type WithVoiceInput = (
    operation: () => Promise<VoiceOutcome | undefined>,
    signal: AbortSignal,
) => Promise<VoiceOutcome | undefined>;

export interface VoiceView {
    phase: string;
    status: string;
    percent?: number;
    preview?: { text: string; caretUtf16: number };
    levels: number[];
}

interface Attempt {
    session?: DesktopDictation;
    abort: AbortController;
    destination: string;
}

export function useVoiceInput(
    destination: string,
    withVoiceInput: WithVoiceInput,
    apply: (
        text: string,
        anchor: VoiceAnchor,
        isCurrent: () => boolean,
    ) => Promise<void>,
) {
    const [view, setView] = useState<VoiceView>();
    const [error, setError] = useState<string>();
    const active = useRef<Attempt | undefined>(undefined);
    const mounted = useRef(true);
    const currentDestination = useRef(destination);
    currentDestination.current = destination;

    const cancel = useCallback(() => {
        const attempt = active.current;
        if (!attempt) return;
        attempt.abort.abort();
        if (mounted.current)
            setView(
                (previous) =>
                    previous && {
                        ...previous,
                        phase: "cancelling",
                        status: "Cancelling…",
                        preview: undefined,
                    },
            );
        void attempt.session
            ?.cancel()
            .catch((error: unknown) =>
                log.warn("Voice cancellation failed", { error }),
            );
    }, []);

    const finish = useCallback(async () => {
        const attempt = active.current;
        if (!attempt?.session || attempt.abort.signal.aborted) return;
        setView(
            (previous) =>
                previous && {
                    ...previous,
                    phase: "finishing",
                    status: "Finishing…",
                },
        );
        try {
            await attempt.session.finish();
        } catch (error) {
            if (active.current === attempt && mounted.current)
                setError(String(error));
            cancel();
        }
    }, [cancel]);

    useEffect(() => {
        if (active.current?.destination !== destination) cancel();
        setError(undefined);
    }, [destination, cancel]);
    useEffect(() => {
        mounted.current = true;
        const onHidden = () => {
            const attempt = active.current;
            if (!document.hidden || !attempt) return;
            if (attempt.session?.hasStarted) {
                void finish();
            } else {
                cancel();
            }
        };
        document.addEventListener("visibilitychange", onHidden);
        window.addEventListener("pagehide", cancel);
        return () => {
            mounted.current = false;
            cancel();
            document.removeEventListener("visibilitychange", onHidden);
            window.removeEventListener("pagehide", cancel);
        };
    }, [cancel, finish]);

    const start = async (anchor: VoiceAnchor, original: string) => {
        if (active.current) return;
        const attempt: Attempt = { abort: new AbortController(), destination };
        active.current = attempt;
        let previewText = "";
        const isCurrent = () =>
            mounted.current &&
            active.current === attempt &&
            !attempt.abort.signal.aborted &&
            currentDestination.current === attempt.destination;
        setError(undefined);
        setView({
            phase: "preparing",
            status: "Preparing voice input…",
            levels: [],
        });
        try {
            const transport = await abortable(
                voiceTransport(),
                attempt.abort.signal,
            );
            const session = new DesktopDictation(transport);
            attempt.session = session;
            if (!isCurrent()) {
                await attempt.session.cancel();
                return;
            }
            const result = await withVoiceInput(
                () =>
                    session.run((event) => {
                        if (!isCurrent()) return;
                        if (event.type === "progress") {
                            setView(
                                (previous) =>
                                    previous && {
                                        ...previous,
                                        percent: event.percent,
                                        status: event.status,
                                    },
                            );
                        } else if (event.type === "snapshot") {
                            setView((previous) => {
                                if (!previous || previous.phase === "finishing")
                                    return previous;
                                return {
                                    ...previous,
                                    phase: event.phase,
                                    status:
                                        event.phase === "finishing" ||
                                        event.phase === "ready"
                                            ? "Finishing…"
                                            : "Listening…",
                                    levels: [
                                        ...previous.levels.slice(-31),
                                        event.level,
                                    ],
                                };
                            });
                            const text = event.text + event.hypothesis;
                            if (text !== previewText) {
                                previewText = text;
                                if (!text.trim()) {
                                    setView(
                                        (previous) =>
                                            previous && {
                                                ...previous,
                                                preview: undefined,
                                            },
                                    );
                                } else {
                                    void insertVoiceText({
                                        anchor,
                                        destination,
                                        revision: anchor.revision,
                                        text: original,
                                        voiceText: text,
                                        composing: false,
                                    })
                                        .then((preview) => {
                                            if (
                                                isCurrent() &&
                                                previewText === text
                                            )
                                                setView(
                                                    (previous) =>
                                                        previous && {
                                                            ...previous,
                                                            preview,
                                                        },
                                                );
                                        })
                                        .catch((error: unknown) =>
                                            log.warn("Voice preview failed", {
                                                error,
                                            }),
                                        );
                                }
                            }
                        }
                    }),
                attempt.abort.signal,
            );
            if (!isCurrent() || !result) return;
            if (result.text.trim()) await apply(result.text, anchor, isCurrent);
            if (isCurrent()) {
                if (result.incomplete)
                    setError(
                        "Only part of your recording could be transcribed. Review the inserted text.",
                    );
                else if (!result.text.trim())
                    setError("No speech detected. Try again.");
            }
        } catch (error: unknown) {
            if (isCurrent()) {
                const message =
                    error && typeof error === "object" && "message" in error
                        ? String(error.message)
                        : String(error);
                setError(message);
            }
        } finally {
            if (active.current === attempt) {
                active.current = undefined;
                if (mounted.current) setView(undefined);
            }
        }
    };

    return { view, error, start, finish, cancel, busy: () => !!active.current };
}
