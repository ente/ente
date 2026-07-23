import type {
    PasteResolvedMode,
    PasteThemeTokens,
} from "@/features/paste/theme/pasteThemeTokens";
import CloseRoundedIcon from "@mui/icons-material/CloseRounded";
import { Box, IconButton } from "@mui/material";
import useMediaQuery from "@mui/material/useMediaQuery";
import { useEffect, useMemo, useRef, useState } from "react";
import {
    getPasteQrCodeOptions,
    getQrModuleCount,
    getQrRenderMetrics,
    isQRCodeStylingModule,
    type QRCodeStylingInstance,
} from "./qrCode";

interface PasteQrCodeProps {
    value: string;
    tokens: PasteThemeTokens;
    size?: number;
    paperBg?: string;
    borderRadius?: string;
    showCenterLock?: boolean;
    /** When set, shows a floating close control (e.g. to dismiss the QR panel). */
    onClose?: () => void;
    /** Color mode for close button hover; pass when `onClose` is used. */
    resolvedMode?: PasteResolvedMode;
}

const QR_LOAD_ERROR_LABEL = "QR unavailable. Refresh to try again.";

export const PasteQrCode = ({
    value,
    tokens,
    size,
    paperBg,
    borderRadius,
    showCenterLock = false,
    onClose,
    resolvedMode,
}: PasteQrCodeProps) => {
    const qrContainerRef = useRef<HTMLDivElement | null>(null);
    const qrCodeRef = useRef<QRCodeStylingInstance | null>(null);
    const moduleCountCacheRef = useRef(new Map<string, number>());
    const [qrLoadError, setQrLoadError] = useState(false);
    const isMdUp = useMediaQuery("(min-width:900px)", { noSsr: true });
    const qrSize = size ?? (isMdUp ? 184 : 168);
    const qrPaperBg = paperBg ?? tokens.qr.paperBg;

    const qrOptions = useMemo(
        () =>
            getPasteQrCodeOptions({
                value,
                qrSize,
                qrPaperBg,
                tokens,
                showCenterLock,
            }),
        [qrSize, showCenterLock, tokens, qrPaperBg, value],
    );

    useEffect(() => {
        let isActive = true;

        const renderQr = async () => {
            try {
                const qrCodeStylingModule =
                    (await import("qr-code-styling")) as unknown;
                if (!isActive) return;

                const container = qrContainerRef.current;
                if (!container) return;
                if (!isQRCodeStylingModule(qrCodeStylingModule)) {
                    throw new Error("Failed to load qr-code-styling");
                }

                const { default: QRCodeStyling } = qrCodeStylingModule;
                const getResolvedQrOptions = (moduleCount: number) => {
                    const { renderSize, margin } = getQrRenderMetrics(
                        qrSize,
                        moduleCount,
                    );

                    return {
                        ...qrOptions,
                        width: renderSize,
                        height: renderSize,
                        margin,
                    };
                };

                const cachedModuleCount =
                    moduleCountCacheRef.current.get(value);

                if (cachedModuleCount !== undefined) {
                    const resolvedQrOptions =
                        getResolvedQrOptions(cachedModuleCount);

                    if (!qrCodeRef.current) {
                        const qrCode = new QRCodeStyling(resolvedQrOptions);
                        qrCode.append(container);
                        qrCodeRef.current = qrCode;
                    } else {
                        qrCodeRef.current.update(resolvedQrOptions);
                    }
                } else if (!qrCodeRef.current) {
                    // Reuse qr-code-styling's internal QR matrix instead of
                    // lazy-loading a second encoder bundle.
                    const qrCode = new QRCodeStyling(qrOptions);
                    const moduleCount = getQrModuleCount(qrCode);

                    if (moduleCount !== undefined) {
                        moduleCountCacheRef.current.set(value, moduleCount);
                        qrCode.update(getResolvedQrOptions(moduleCount));
                    }

                    qrCode.append(container);
                    qrCodeRef.current = qrCode;
                } else {
                    qrCodeRef.current.update(qrOptions);

                    const moduleCount = getQrModuleCount(qrCodeRef.current);
                    if (moduleCount !== undefined) {
                        moduleCountCacheRef.current.set(value, moduleCount);
                        qrCodeRef.current.update(
                            getResolvedQrOptions(moduleCount),
                        );
                    }
                }

                setQrLoadError(false);
            } catch {
                if (!isActive) return;

                setQrLoadError(true);
            }
        };

        void renderQr();

        return () => {
            isActive = false;
        };
    }, [qrOptions, qrSize, value]);

    useEffect(
        () => () => {
            qrCodeRef.current = null;
            qrContainerRef.current?.replaceChildren();
        },
        [],
    );

    const qrBox = (
        <Box
            ref={qrContainerRef}
            role={qrLoadError ? "status" : "img"}
            aria-label={
                qrLoadError ? QR_LOAD_ERROR_LABEL : "QR code for paste link"
            }
            sx={{
                display: "grid",
                placeItems: "center",
                width: { xs: 144, sm: 168, md: 184 },
                height: { xs: 144, sm: 168, md: 184 },
                ...(size ? { width: qrSize, height: qrSize } : {}),
                borderRadius: borderRadius ?? "10px",
                bgcolor: qrPaperBg,
                overflow: "hidden",
                ...(qrLoadError && {
                    px: 2,
                    "&::after": {
                        content: `"${QR_LOAD_ERROR_LABEL}"`,
                        color: tokens.text.secondary,
                        fontSize: "0.75rem",
                        lineHeight: 1.4,
                        textAlign: "center",
                    },
                }),
                "& svg, & canvas": {
                    display: "block",
                    width: "100% !important",
                    height: "100% !important",
                },
            }}
        />
    );

    if (!onClose) {
        return qrBox;
    }

    const isDark = resolvedMode === "dark";

    return (
        <Box
            sx={{
                position: "relative",
                width: "fit-content",
                maxWidth: "100%",
                mx: "auto",
                overflow: "visible",
            }}
        >
            {qrBox}
            <IconButton
                type="button"
                aria-label="Close QR code"
                disableRipple
                onClick={onClose}
                sx={{
                    position: "absolute",
                    top: 0,
                    right: 0,
                    zIndex: 1,
                    width: 28,
                    height: 28,
                    minWidth: 28,
                    padding: 0,
                    borderRadius: "50%",
                    border: `1px solid ${tokens.button.qrToggleBorder}`,
                    color: tokens.text.secondary,
                    bgcolor: tokens.surface.floatingCardBg,
                    opacity: 1,
                    boxShadow:
                        "0 2px 8px rgba(0, 0, 0, 0.1), 0 1px 2px rgba(0, 0, 0, 0.05)",
                    transform: "translate(50%, -50%) scale(1)",
                    transformOrigin: "center",
                    transition:
                        "transform 420ms cubic-bezier(0.22, 1, 0.36, 1), background-color 420ms cubic-bezier(0.22, 1, 0.36, 1)",
                    "&:hover": {
                        opacity: 1,
                        transform: "translate(50%, -50%) scale(1.12)",
                        bgcolor: isDark
                            ? "rgba(26, 36, 72, 1)"
                            : "rgba(237, 244, 255, 1)",
                    },
                    "& .MuiSvgIcon-root": { opacity: 1 },
                }}
            >
                <CloseRoundedIcon sx={{ fontSize: 16 }} />
            </IconButton>
        </Box>
    );
};
