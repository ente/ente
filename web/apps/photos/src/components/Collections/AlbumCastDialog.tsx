import { publishCastPayload, revokeAllCastTokens } from "@/services/cast";
import { loadCast } from "@/utils/chromecast-sender";
import { Link, Stack, Typography } from "@mui/material";
import { TitledMiniDialog } from "ente-base/components/MiniDialog";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import {
    SingleInputForm,
    type SingleInputFormProps,
} from "ente-base/components/SingleInputForm";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { isNamedError } from "ente-base/error";
import { ut } from "ente-base/i18n";
import log from "ente-base/log";
import type { Collection } from "ente-media/collection";
import { useSettingsSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import { t } from "i18next";
import React, { useCallback, useEffect, useState } from "react";
import { Trans } from "react-i18next";
import { z } from "zod";

type AlbumCastDialogProps = ModalVisibilityProps & { collection: Collection };

export const AlbumCastDialog: React.FC<AlbumCastDialogProps> = ({
    open,
    onClose,
    collection,
}) => (
    <TitledMiniDialog {...{ open, onClose }} title={t("cast_album_to_tv")}>
        <AlbumCastDialogContents {...{ open, onClose, collection }} />
    </TitledMiniDialog>
);

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
        // @ts-expect-error TODO: why is this needed
        // eslint-disable-next-line @typescript-eslint/dot-notation
        setBrowserCanCast(typeof window["chrome"] != "undefined");
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
        if (view == "auto") {
            void loadCast().then(async (cast) => {
                const instance = cast.framework.CastContext.getInstance();
                try {
                    await instance.requestSession();
                } catch (e) {
                    setView("auto-cast-error");
                    log.error("Error requesting session", e);
                    return;
                }
                const session = instance.getCurrentSession()!;
                session.addMessageListener(
                    "urn:x-cast:pair-request",
                    (_, message) => {
                        const { code } = CastPairRequest.parse(
                            JSON.parse(message),
                        );

                        void publishCastPayload(code, collection)
                            .then(() => {
                                setView("choose");
                                onClose();
                            })
                            .catch((e: unknown) => {
                                log.error("Error casting to TV", e);
                                setView("auto-cast-error");
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
    }, [onClose, view, collection]);

    useEffect(() => {
        // Start every open with new server-side sessions.
        // Revocation cannot affect this client, so do not block on it.
        if (open) void revokeAllCastTokens();
    }, [open]);

    return (
        <>
            {view == "choose" && (
                <Stack sx={{ py: 1, gap: 4 }}>
                    {browserCanCast && (
                        <Stack sx={{ gap: 2 }}>
                            <Typography sx={{ color: "text.muted" }}>
                                {t("cast_auto_pair_description")}
                            </Typography>

                            <FocusVisibleButton onClick={() => setView("auto")}>
                                {t("cast_auto_pair")}
                            </FocusVisibleButton>
                        </Stack>
                    )}
                    <Stack sx={{ gap: 2 }}>
                        <Typography sx={{ color: "text.muted" }}>
                            {t("pair_with_pin_description")}
                        </Typography>
                        <FocusVisibleButton onClick={() => setView("pin")}>
                            {t("pair_with_pin")}
                        </FocusVisibleButton>
                    </Stack>
                </Stack>
            )}
            {view == "auto" && (
                <Stack sx={{ pt: 1, gap: 3, textAlign: "center" }}>
                    <div>
                        <ActivityIndicator />
                    </div>
                    <Typography>{t("choose_device_from_browser")}</Typography>
                    <FocusVisibleButton
                        color="secondary"
                        onClick={() => setView("choose")}
                    >
                        {t("go_back")}
                    </FocusVisibleButton>
                </Stack>
            )}
            {view == "auto-cast-error" && (
                <Stack sx={{ pt: 1, gap: 3, textAlign: "center" }}>
                    <Typography>{t("cast_auto_pair_failed")}</Typography>
                    <FocusVisibleButton
                        color="secondary"
                        onClick={() => setView("choose")}
                    >
                        {t("go_back")}
                    </FocusVisibleButton>
                </Stack>
            )}
            {view == "pin" && (
                <>
                    <Stack sx={{ gap: 2, mb: 2 }}>
                        <Typography sx={{ color: "text.muted" }}>
                            <Trans
                                i18nKey="visit_cast_url"
                                components={{
                                    a: <Link target="_blank" href={castURL} />,
                                }}
                                values={{ url: castHost }}
                            />
                        </Typography>
                        <Typography sx={{ color: "text.muted" }}>
                            {t("enter_cast_pin_code")}
                        </Typography>
                    </Stack>
                    <SingleInputForm
                        label={t("code")}
                        placeholder={ut("123456")}
                        submitButtonTitle={t("pair_device_to_tv")}
                        onSubmit={onSubmit}
                    />
                    <FocusVisibleButton
                        variant="text"
                        fullWidth
                        onClick={() => setView("choose")}
                        sx={{ mt: 1 }}
                    >
                        {t("go_back")}
                    </FocusVisibleButton>
                </>
            )}
        </>
    );
};

const CastPairRequest = z.object({ code: z.string() });
