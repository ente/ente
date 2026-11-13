import { publishCastPayload, revokeAllCastTokens } from "@/services/cast";
import { loadCast } from "@/utils/chromecast-sender";
import { externalLink } from "@/utils/link";
import {
    AlertCircleIcon,
    ArrowLeft02Icon,
    ArrowRight01Icon,
    Cancel01Icon,
    CastIcon,
    KeyboardIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Box,
    Dialog,
    IconButton,
    Stack,
    Typography,
    type Theme,
} from "@mui/material";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import {
    v2CloseButtonSx,
    v2HeaderRowSx,
    v2PaperSx,
    v2TitleSx,
} from "ente-base/components/SingleInput.styles";
import {
    SingleInputForm,
    type SingleInputFormProps,
} from "ente-base/components/SingleInputForm";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { isSxArray } from "ente-base/components/utils/sx";
import { isNamedError } from "ente-base/error";
import { ut } from "ente-base/i18n";
import log from "ente-base/log";
import type { Collection } from "ente-media/collection";
import { FocusVisibleUnstyledButton } from "ente-new/photos/components/UnstyledButton";
import { useSettingsSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import { t } from "i18next";
import React, { useCallback, useEffect, useId, useState } from "react";
import { Trans } from "react-i18next";
import { z } from "zod";

type AlbumCastDialogProps = ModalVisibilityProps & { collection: Collection };

export const AlbumCastDialog: React.FC<AlbumCastDialogProps> = ({
    open,
    onClose,
    collection,
}) => {
    const titleID = useId();
    return (
        <Dialog
            {...{ open, onClose }}
            maxWidth={false}
            aria-labelledby={titleID}
            slotProps={{
                paper: {
                    sx: [
                        ...(isSxArray(v2PaperSx) ? v2PaperSx : [v2PaperSx]),
                        {
                            width: "min(560px, calc(100svw - 32px))",
                            maxWidth: "560px",
                        },
                    ],
                },
            }}
        >
            <Stack sx={{ p: "24px", gap: "24px" }}>
                <Stack sx={{ gap: "16px" }}>
                    <Stack direction="row" sx={v2HeaderRowSx}>
                        <Typography
                            id={titleID}
                            component="h2"
                            sx={{
                                ...v2TitleSx,
                                fontFamily: "'Outfit Variable', sans-serif",
                            }}
                        >
                            {t("cast_album_to_tv")}
                        </Typography>
                        <IconButton
                            aria-label={t("close")}
                            onClick={onClose}
                            sx={v2CloseButtonSx}
                        >
                            <HugeiconsIcon
                                icon={Cancel01Icon}
                                size={18}
                                aria-hidden
                            />
                        </IconButton>
                    </Stack>
                </Stack>
                <AlbumCastDialogContents {...{ open, onClose, collection }} />
            </Stack>
        </Dialog>
    );
};

// MUI preserves a dialog child's state while hidden.
// Keep contents separate so each open starts fresh and reruns effects.
const AlbumCastDialogContents: React.FC<AlbumCastDialogProps> = ({
    open,
    onClose,
    collection,
}) => {
    const { castURL } = useSettingsSnapshot();

    const [view, setView] = useState<
        "choose" | "auto" | "pin" | "auto-cast-error"
    >("choose");

    const [browserCanCast, setBrowserCanCast] = useState(false);

    const castHost = new URL(castURL).host;

    useEffect(() => {
        setBrowserCanCast(typeof window.chrome != "undefined");
    }, []);

    const onSubmit: SingleInputFormProps["onSubmit"] = useCallback(
        async (value, setFieldError) => {
            try {
                await publishCastPayload(value.trim(), collection);
                onClose();
            } catch (e) {
                log.error("Failed to cast", e);
                if (isNamedError(e, "cast_device_not_found")) {
                    setFieldError(t("tv_not_found"));
                } else {
                    throw e;
                }
            }
        },
        [onClose, collection],
    );

    useEffect(() => {
        let active = true;
        const isActive = () => active;
        if (view == "auto") {
            void loadCast().then(async (cast) => {
                if (!isActive()) return;
                const instance = cast.framework.CastContext.getInstance();
                try {
                    await instance.requestSession();
                } catch (e) {
                    if (isActive()) setView("auto-cast-error");
                    log.error("Error requesting session", e);
                    return;
                }
                if (!isActive()) return;
                const session = instance.getCurrentSession()!;
                session.addMessageListener(
                    "urn:x-cast:pair-request",
                    (_, message) => {
                        if (!isActive()) return;
                        const { code } = CastPairRequest.parse(
                            JSON.parse(message),
                        );

                        void publishCastPayload(code, collection)
                            .then(() => {
                                if (!isActive()) return;
                                setView("choose");
                                onClose();
                            })
                            .catch((e: unknown) => {
                                log.error("Error casting to TV", e);
                                if (isActive()) setView("auto-cast-error");
                            });
                    },
                );

                const collectionID = collection.id;
                void session
                    .sendMessage("urn:x-cast:pair-request", { collectionID })
                    .then(() => {
                        log.debug(() => "urn:x-cast:pair-request sent");
                    });
            });
        }
        return () => {
            active = false;
        };
    }, [onClose, view, collection]);

    useEffect(() => {
        // Start every open with new server-side sessions.
        // Revocation cannot affect this client, so do not block on it.
        if (open) void revokeAllCastTokens();
    }, [open]);

    return (
        <>
            {view == "choose" && (
                <Stack sx={{ gap: "12px" }}>
                    {browserCanCast && (
                        <PairingOption
                            icon={
                                <HugeiconsIcon
                                    icon={CastIcon}
                                    size={24}
                                    strokeWidth={1.5}
                                    aria-hidden
                                />
                            }
                            title={t("cast_auto_pair")}
                            description={t("cast_auto_pair_description")}
                            onClick={() => setView("auto")}
                        />
                    )}
                    <PairingOption
                        icon={
                            <HugeiconsIcon
                                icon={KeyboardIcon}
                                size={24}
                                strokeWidth={1.5}
                                aria-hidden
                            />
                        }
                        title={t("pair_with_pin")}
                        description={t("pair_with_pin_description")}
                        onClick={() => setView("pin")}
                    />
                </Stack>
            )}
            {(view == "auto" || view == "auto-cast-error") && (
                <Stack sx={{ gap: "16px" }}>
                    <Stack
                        sx={{
                            alignItems: "center",
                            textAlign: "center",
                            pt: "6px",
                            pb: "12px",
                        }}
                    >
                        <Box sx={castIconSx}>
                            <HugeiconsIcon
                                icon={
                                    view == "auto" ? CastIcon : AlertCircleIcon
                                }
                                size={28}
                                strokeWidth={1.5}
                                aria-hidden
                            />
                        </Box>
                        <Typography
                            component="h3"
                            sx={{
                                fontFamily: "'Outfit Variable', sans-serif",
                                fontSize: 20,
                                lineHeight: "28px",
                                fontWeight: 500,
                                mb: 1,
                            }}
                        >
                            {t(
                                view == "auto"
                                    ? "choose_cast_device"
                                    : "cast_connection_failed",
                            )}
                        </Typography>
                        <Typography sx={instructionSx}>
                            {t(
                                view == "auto"
                                    ? "choose_device_from_browser"
                                    : "cast_auto_pair_failed",
                            )}
                        </Typography>
                    </Stack>
                    <FocusVisibleButton
                        color="secondary"
                        startIcon={
                            <HugeiconsIcon
                                icon={ArrowLeft02Icon}
                                size={18}
                                aria-hidden
                            />
                        }
                        onClick={() => setView("choose")}
                        sx={secondaryButtonSx}
                    >
                        {t("go_back")}
                    </FocusVisibleButton>
                </Stack>
            )}
            {view == "pin" && (
                <Stack sx={{ gap: "20px" }}>
                    <FocusVisibleUnstyledButton
                        onClick={() => setView("choose")}
                        sx={{
                            display: "inline-flex",
                            gap: 1,
                            alignItems: "center",
                            alignSelf: "flex-start",
                            minHeight: 36,
                            fontSize: 14,
                            fontWeight: 500,
                            color: "text.muted",
                            "&:hover": { color: "text.base" },
                        }}
                    >
                        <HugeiconsIcon
                            icon={ArrowLeft02Icon}
                            size={18}
                            aria-hidden
                        />
                        {t("go_back")}
                    </FocusVisibleUnstyledButton>
                    <Stack
                        component="ol"
                        role="list"
                        sx={{ listStyle: "none", m: 0, p: 0, gap: "14px" }}
                    >
                        <Stack
                            component="li"
                            direction="row"
                            sx={{ gap: "12px", alignItems: "flex-start" }}
                        >
                            <Box component="span" sx={stepNumberSx}>
                                1
                            </Box>
                            <Typography sx={instructionSx}>
                                <Trans
                                    i18nKey="visit_cast_url"
                                    components={{ a: externalLink(castURL) }}
                                    values={{ url: castHost }}
                                />
                            </Typography>
                        </Stack>
                        <Stack
                            component="li"
                            direction="row"
                            sx={{ gap: "12px", alignItems: "flex-start" }}
                        >
                            <Box component="span" sx={stepNumberSx}>
                                2
                            </Box>
                            <Typography sx={instructionSx}>
                                {t("enter_cast_pin_code")}
                            </Typography>
                        </Stack>
                    </Stack>
                    <SingleInputForm
                        label={t("code")}
                        placeholder={ut("123456")}
                        submitButtonTitle={t("pair_device_to_tv")}
                        onSubmit={onSubmit}
                    />
                </Stack>
            )}
        </>
    );
};

const CastPairRequest = z.object({ code: z.string() });

const instructionSx = { fontSize: 14, lineHeight: "22px", color: "text.muted" };

const castIconSx = (theme: Theme) => ({
    display: "grid",
    placeItems: "center",
    width: 56,
    height: 56,
    borderRadius: "18px",
    mb: "18px",
    backgroundColor: "background.paper",
    ...theme.applyStyles("dark", { backgroundColor: "#282828" }),
});

const secondaryButtonSx = {
    minHeight: 52,
    borderRadius: "16px",
    fontSize: 14,
    fontWeight: 500,
};

const stepNumberSx = (theme: Theme) => ({
    display: "grid",
    placeItems: "center",
    flexShrink: 0,
    width: 24,
    height: 24,
    borderRadius: "50%",
    backgroundColor: "background.paper",
    color: "text.muted",
    fontSize: 12,
    fontWeight: 500,
    ...theme.applyStyles("dark", { backgroundColor: "#282828" }),
});

const PairingOption: React.FC<{
    icon: React.ReactNode;
    title: string;
    description: string;
    onClick: () => void;
}> = ({ icon, title, description, onClick }) => (
    <FocusVisibleUnstyledButton
        onClick={onClick}
        sx={(theme) => ({
            display: "flex",
            alignItems: "center",
            gap: "14px",
            width: "100%",
            boxSizing: "border-box",
            p: "18px 14px",
            borderRadius: "16px",
            textAlign: "left",
            color: "text.base",
            backgroundColor: "background.paper",
            "&:hover": { backgroundColor: "fill.faintHover" },
            ...theme.applyStyles("dark", { backgroundColor: "#282828" }),
        })}
    >
        <Box
            sx={{
                width: 36,
                height: 36,
                flexShrink: 0,
                display: "grid",
                placeItems: "center",
            }}
        >
            {icon}
        </Box>
        <Stack sx={{ flex: 1, minWidth: 0, gap: "4px" }}>
            <Typography sx={{ fontSize: 14, fontWeight: 500 }}>
                {title}
            </Typography>
            <Typography
                sx={{ fontSize: 12, lineHeight: "18px", color: "text.muted" }}
            >
                {description}
            </Typography>
        </Stack>
        <Box sx={{ display: "flex", color: "text.muted", flexShrink: 0 }}>
            <HugeiconsIcon icon={ArrowRight01Icon} size={18} aria-hidden />
        </Box>
    </FocusVisibleUnstyledButton>
);
