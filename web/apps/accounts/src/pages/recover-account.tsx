import {
    accountRecoveryErrorCode,
    recoverAccount,
    validateAccountRecovery,
    type AccountRecoveryErrorCode,
} from "@/services/account-recovery";
import InfoOutlinedIcon from "@mui/icons-material/InfoOutlined";
import { Box, Stack, Typography } from "@mui/material";
import { AccountsPageContents } from "ente-accounts/components/layouts/centered-paper";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { useBaseContext } from "ente-base/context";
import { t } from "i18next";
import React, { useCallback, useEffect, useState } from "react";

type Phase =
    | "loading"
    | "ready"
    | "recovering"
    | "recovered"
    | AccountRecoveryErrorPhase
    | "failed";

type AccountRecoveryErrorPhase =
    | "invalid"
    | "expired"
    | "emailInUse"
    | "unavailable";

const accountRecoveryErrorPhases: Record<
    AccountRecoveryErrorCode,
    AccountRecoveryErrorPhase
> = {
    ACCOUNT_RECOVERY_INVALID_LINK: "invalid",
    ACCOUNT_RECOVERY_LINK_EXPIRED: "expired",
    ACCOUNT_RECOVERY_EMAIL_IN_USE: "emailInUse",
    ACCOUNT_RECOVERY_UNAVAILABLE: "unavailable",
};

const Page: React.FC = () => {
    const { onGenericError } = useBaseContext();
    const [phase, setPhase] = useState<Phase>("loading");
    const [token, setToken] = useState<string>();

    const handleError = useCallback(
        async (error: unknown) => {
            const code = await accountRecoveryErrorCode(error);
            if (code) {
                setPhase(accountRecoveryErrorPhases[code]);
            } else {
                setPhase("failed");
                onGenericError(error);
            }
        },
        [onGenericError],
    );

    const validate = useCallback(
        async (token: string) => {
            setPhase("loading");
            try {
                const response = await validateAccountRecovery(token);
                const recovered = response.status == "recovered";
                if (recovered) {
                    window.history.replaceState(
                        null,
                        "",
                        window.location.pathname,
                    );
                }
                setPhase(recovered ? "recovered" : "ready");
            } catch (error) {
                await handleError(error);
            }
        },
        [handleError],
    );

    useEffect(() => {
        const reloadForNewToken = () => window.location.reload();
        window.addEventListener("hashchange", reloadForNewToken);

        const token = new URLSearchParams(window.location.hash.slice(1)).get(
            "recoveryToken",
        );
        if (!token) {
            setPhase("invalid");
        } else {
            setToken(token);
            void validate(token);
        }

        return () =>
            window.removeEventListener("hashchange", reloadForNewToken);
    }, [validate]);

    const recover = async () => {
        setPhase("recovering");
        try {
            await recoverAccount(token!);
            window.history.replaceState(null, "", window.location.pathname);
            setPhase("recovered");
        } catch (error) {
            await handleError(error);
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
            ) : phase == "failed" ? (
                <RecoveryContents>
                    <Typography variant="h3">
                        {t("generic_error_retry")}
                    </Typography>
                    <FocusVisibleButton onClick={() => void validate(token!)}>
                        {t("retry")}
                    </FocusVisibleButton>
                </RecoveryContents>
            ) : phase == "recovered" ? (
                <RecoveryContents>
                    <RecoveryIcon />
                    <RecoveryMessage
                        title={t("account_recovery_success")}
                        description={t("account_recovery_success_description")}
                    />
                    <FocusVisibleButton color="accent" href="https://ente.com">
                        {t("open_ente")}
                    </FocusVisibleButton>
                </RecoveryContents>
            ) : phase == "invalid" ? (
                <RecoveryContents>
                    <RecoveryMessage
                        title={t("account_recovery_invalid_title")}
                        description={t("account_recovery_invalid_description")}
                    />
                </RecoveryContents>
            ) : phase == "expired" ? (
                <RecoveryContents>
                    <RecoveryMessage
                        title={t("account_recovery_expired_title")}
                        description={t("account_recovery_expired_description")}
                    />
                </RecoveryContents>
            ) : phase == "emailInUse" ? (
                <RecoveryContents>
                    <InfoOutlinedIcon color="secondary" sx={{ fontSize: 48 }} />
                    <RecoveryMessage
                        title={t("account_recovery_email_in_use")}
                        description={t(
                            "account_recovery_email_in_use_description",
                        )}
                    />
                </RecoveryContents>
            ) : phase == "unavailable" ? (
                <RecoveryContents>
                    <RecoveryMessage
                        title={t("account_recovery_unavailable_title")}
                        description={t(
                            "account_recovery_unavailable_description",
                        )}
                    />
                </RecoveryContents>
            ) : (
                <RecoveryContents>
                    <RecoveryIcon />
                    <RecoveryMessage
                        title={t("account_recovery_title")}
                        description={t("account_recovery_description")}
                    />
                    <LoadingButton
                        fullWidth
                        color="accent"
                        loading={phase == "recovering"}
                        onClick={() => void recover()}
                    >
                        {t("recover_account")}
                    </LoadingButton>
                </RecoveryContents>
            )}
        </AccountsPageContents>
    );
};

const RecoveryIcon = () => (
    <Box
        component="img"
        alt=""
        src="/images/ente-circular.png"
        sx={{ width: 96, height: 96 }}
    />
);

const RecoveryMessage: React.FC<{ title: string; description: string }> = ({
    title,
    description,
}) => (
    <Stack sx={{ gap: 1.5 }}>
        <Typography variant="h3">{title}</Typography>
        <Typography sx={{ color: "text.muted" }}>{description}</Typography>
    </Stack>
);

const RecoveryContents: React.FC<React.PropsWithChildren> = ({ children }) => (
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
