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
import {
    v2PaperSx,
    v2SubmitButtonSx,
} from "ente-base/components/SingleInput.styles";
import { isSxArray } from "ente-base/components/utils/sx";
import { useBaseContext } from "ente-base/context";
import { isHTTPErrorWithStatus } from "ente-base/http";
import { t } from "i18next";
import { useRouter } from "next/router";
import React, { useCallback, useEffect, useRef, useState } from "react";

type Phase =
    "loading" | "ready" | "accepting" | "accepted" | "invalid" | "failed";

const Page: React.FC = () => {
    const router = useRouter();
    const { onGenericError } = useBaseContext();
    const [phase, setPhase] = useState<Phase>("loading");
    const [invite, setInvite] = useState<FamilyInviteInfo>();
    const token = useRef<string | null>(null);

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
        // Hydration can restore the original URL until the router is ready.
        if (!router.isReady) return;
        token.current ??= new URLSearchParams(
            window.location.hash.slice(1),
        ).get("inviteToken");
        if (!token.current) {
            setPhase("invalid");
            return;
        }
        window.history.replaceState(null, "", window.location.pathname);
        void loadInvite(token.current);
    }, [loadInvite, router.isReady]);

    const accept = async () => {
        setPhase("accepting");
        try {
            setInvite(await acceptFamilyInvite(token.current!));
            setPhase("accepted");
        } catch (e) {
            const invalid =
                isHTTPErrorWithStatus(e, 401) || isHTTPErrorWithStatus(e, 404);
            setPhase(invalid ? "invalid" : "ready");
            if (!invalid) onGenericError(e);
        }
    };

    const accepting = phase == "accepting";
    const title = t(
        phase == "accepted"
            ? "family_invite_accepted"
            : phase == "invalid" || phase == "loading"
              ? "family_plan"
              : phase == "failed"
                ? "generic_error_retry"
                : "family_invite_title",
    );

    return (
        <AccountsPageContents
            paperSx={[
                ...(isSxArray(v2PaperSx) ? v2PaperSx : [v2PaperSx]),
                {
                    width: "min(420px, calc(100svw - 32px))",
                    maxWidth: 420,
                    boxSizing: "border-box",
                    "&&": { p: "20px" },
                    minHeight: 0,
                    gap: "20px",
                },
            ]}
        >
            <Typography
                component="h1"
                sx={{ fontSize: 20, lineHeight: "28px", fontWeight: 600 }}
            >
                {title}
            </Typography>
            {phase == "loading" ? (
                <Stack sx={{ alignItems: "center", py: 4 }}>
                    <ActivityIndicator />
                </Stack>
            ) : phase == "invalid" ? (
                <FamilyInviteContents>
                    <FamilyInviteIllustration src="/images/family-invite-invalid.png" />
                    <FamilyInviteDescription>
                        {t("family_invite_invalid")}
                    </FamilyInviteDescription>
                </FamilyInviteContents>
            ) : phase == "failed" ? (
                <FocusVisibleButton
                    fullWidth
                    sx={{ ...v2SubmitButtonSx, flex: "none", fontWeight: 600 }}
                    onClick={() => void loadInvite(token.current!)}
                >
                    {t("retry")}
                </FocusVisibleButton>
            ) : phase == "accepted" ? (
                <FamilyInviteContents>
                    <FamilyInviteIllustration src="/images/family-invite-accepted.png" />
                    <FamilyInviteDescription>
                        {t("family_invite_accepted_description", {
                            email: invite?.adminEmail,
                        })}
                    </FamilyInviteDescription>
                    <FocusVisibleButton
                        fullWidth
                        href="https://photos.ente.com"
                        sx={{
                            ...v2SubmitButtonSx,
                            flex: "none",
                            fontWeight: 600,
                        }}
                    >
                        {t("open_ente")}
                    </FocusVisibleButton>
                </FamilyInviteContents>
            ) : (
                <FamilyInviteContents>
                    <FamilyInviteIllustration src="/images/family-invite.png" />
                    <FamilyInviteDescription>
                        {t("family_invite_description", {
                            email: invite?.adminEmail,
                        })}
                    </FamilyInviteDescription>
                    <LoadingButton
                        fullWidth
                        disabled={accepting}
                        loading={accepting}
                        sx={{
                            ...v2SubmitButtonSx,
                            flex: "none",
                            fontWeight: 600,
                        }}
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
}) => <Stack sx={{ gap: 2 }}>{children}</Stack>;

const FamilyInviteDescription: React.FC<React.PropsWithChildren> = ({
    children,
}) => (
    <Typography
        sx={{
            fontSize: 14,
            lineHeight: "22px",
            color: "text.muted",
            overflowWrap: "anywhere",
        }}
    >
        {children}
    </Typography>
);

const FamilyInviteIllustration: React.FC<{ src: string }> = ({ src }) => (
    <Box
        sx={(theme) => ({
            height: 142,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            bgcolor: "background.paper",
            borderRadius: "16px",
            ...theme.applyStyles("dark", { bgcolor: "#282828" }),
        })}
    >
        <Box
            component="img"
            alt=""
            src={src}
            sx={{
                maxHeight: 116,
                maxWidth: "min(180px, 100%)",
                objectFit: "contain",
            }}
        />
    </Box>
);

export default Page;
