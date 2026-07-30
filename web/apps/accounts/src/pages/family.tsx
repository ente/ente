import {
    acceptFamilyInvite,
    getFamilyInviteInfo,
    type FamilyInviteInfo,
} from "@/services/family";
import { Box, Stack, Typography } from "@mui/material";
import { AccountsPageContents } from "ente-accounts/components/layouts/centered-paper";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { useBaseContext } from "ente-base/context";
import { isHTTPErrorWithStatus } from "ente-base/http";
import { t } from "i18next";
import React, { useCallback, useEffect, useState } from "react";

type Phase =
    | "loading"
    | "ready"
    | "accepting"
    | "accepted"
    | "invalid"
    | "failed";

const Page: React.FC = () => {
    const { onGenericError } = useBaseContext();
    const [phase, setPhase] = useState<Phase>("loading");
    const [invite, setInvite] = useState<FamilyInviteInfo>();
    const [token, setToken] = useState<string>();

    const loadInvite = useCallback(
        async (token: string) => {
            setPhase("loading");
            try {
                setInvite(await getFamilyInviteInfo(token));
                setPhase("ready");
            } catch (e) {
                const invalid =
                    isHTTPErrorWithStatus(e, 400) ||
                    isHTTPErrorWithStatus(e, 404);
                setPhase(invalid ? "invalid" : "failed");
                if (!invalid) onGenericError(e);
            }
        },
        [onGenericError],
    );

    useEffect(() => {
        const token = new URLSearchParams(window.location.hash.slice(1)).get(
            "inviteToken",
        );
        if (!token) {
            setPhase("invalid");
            return;
        }
        setToken(token);
        void loadInvite(token);
    }, [loadInvite]);

    const accept = async () => {
        setPhase("accepting");
        try {
            setInvite(await acceptFamilyInvite(token!));
            window.history.replaceState(null, "", window.location.pathname);
            setPhase("accepted");
        } catch (e) {
            const invalid =
                isHTTPErrorWithStatus(e, 401) || isHTTPErrorWithStatus(e, 404);
            setPhase(invalid ? "invalid" : "ready");
            if (!invalid) onGenericError(e);
        }
    };

    return (
        <AccountsPageContents>
            {phase == "loading" ? (
                <Stack
                    sx={{
                        flex: 1,
                        placeContent: "center",
                        alignItems: "center",
                    }}
                >
                    <ActivityIndicator />
                </Stack>
            ) : phase == "invalid" ? (
                <FamilyInviteContents>
                    <Box
                        component="img"
                        alt=""
                        src="/images/family-invite-invalid.png"
                        sx={{ width: 180, height: "auto" }}
                    />
                    <Typography sx={{ color: "text.muted" }}>
                        {t("family_invite_invalid")}
                    </Typography>
                </FamilyInviteContents>
            ) : phase == "failed" ? (
                <Stack sx={{ flex: 1, placeContent: "center", gap: 3 }}>
                    <Typography variant="h3" sx={{ textAlign: "center" }}>
                        {t("generic_error_retry")}
                    </Typography>
                    <FocusVisibleButton onClick={() => void loadInvite(token!)}>
                        {t("retry")}
                    </FocusVisibleButton>
                </Stack>
            ) : phase == "accepted" ? (
                <FamilyInviteContents>
                    <Box
                        component="img"
                        alt=""
                        src="/images/family-invite-accepted.png"
                        sx={{ width: 200, height: "auto" }}
                    />
                    <Stack sx={{ gap: 1.5 }}>
                        <Typography variant="h3">
                            {t("family_invite_accepted")}
                        </Typography>
                        <Typography sx={{ color: "text.muted" }}>
                            {t("family_invite_accepted_description", {
                                email: invite?.adminEmail,
                            })}
                        </Typography>
                    </Stack>
                    <FocusVisibleButton
                        color="accent"
                        href="https://photos.ente.com"
                    >
                        {t("open_ente")}
                    </FocusVisibleButton>
                </FamilyInviteContents>
            ) : (
                <FamilyInviteContents>
                    <Box
                        component="img"
                        alt=""
                        src="/images/family-invite.png"
                        sx={{ width: 160, height: "auto" }}
                    />
                    <Stack sx={{ gap: 1.5 }}>
                        <Typography variant="h3">
                            {t("family_invite_title")}
                        </Typography>
                        <Typography sx={{ color: "text.muted" }}>
                            {t("family_invite_description", {
                                email: invite?.adminEmail,
                            })}
                        </Typography>
                    </Stack>
                    <LoadingButton
                        fullWidth
                        color="accent"
                        loading={phase == "accepting"}
                        onClick={() => void accept()}
                    >
                        {t("accept_family_invite")}
                    </LoadingButton>
                </FamilyInviteContents>
            )}
        </AccountsPageContents>
    );
};

const FamilyInviteContents: React.FC<React.PropsWithChildren> = ({
    children,
}) => (
    <Stack
        sx={{
            flex: 1,
            placeContent: "center",
            alignItems: "center",
            textAlign: "center",
            gap: 3,
        }}
    >
        {children}
    </Stack>
);

export default Page;
