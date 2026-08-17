import { Paper, Stack, styled, Typography } from "@mui/material";
import { CodeBlock } from "ente-accounts/components/CodeBlock";
import { Verify2FACodeForm } from "ente-accounts/components/Verify2FACodeForm";
import { appHomeRoute } from "ente-accounts/services/redirect";
import type { TwoFactorSecret } from "ente-accounts/services/user";
import {
    setupTwoFactor,
    setupTwoFactorFinish,
} from "ente-accounts/services/user";
import { CenteredFill } from "ente-base/components/containers";
import { EnteLogo } from "ente-base/components/EnteLogo";
import { LinkButton } from "ente-base/components/LinkButton";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { NavbarBase } from "ente-base/components/Navbar";
import { t } from "i18next";
import { useRouter } from "next/router";
import React, { useEffect, useState } from "react";

const Page: React.FC = () => {
    const [twoFactorSecret, setTwoFactorSecret] = useState<
        TwoFactorSecret | undefined
    >();

    const router = useRouter();

    useEffect(() => {
        void setupTwoFactor().then(setTwoFactorSecret);
    }, []);

    const handleSubmit = async (otp: string) => {
        await setupTwoFactorFinish(twoFactorSecret!.secretCode, otp);
        await router.push(appHomeRoute);
    };

    return (
        <Stack
            sx={[
                { minHeight: "100svh", bgcolor: "secondary.main" },
                (theme) =>
                    theme.applyStyles("dark", {
                        bgcolor: "background.default",
                    }),
            ]}
        >
            <NavbarBase
                sx={{
                    boxShadow: "none",
                    borderBottom: "none",
                    bgcolor: "transparent",
                }}
            >
                <EnteLogo />
            </NavbarBase>
            <CenteredFill>
                <ContentsPaper>
                    <Typography variant="h5" sx={{ textAlign: "center" }}>
                        {t("two_factor")}
                    </Typography>
                    <Instructions twoFactorSecret={twoFactorSecret} />
                    <Verify2FACodeForm
                        onSubmit={handleSubmit}
                        submitButtonText={t("enable")}
                    />
                    <Stack sx={{ alignItems: "center" }}>
                        <FocusVisibleButton
                            variant="text"
                            onClick={router.back}
                        >
                            {t("go_back")}
                        </FocusVisibleButton>
                    </Stack>
                </ContentsPaper>
            </CenteredFill>
        </Stack>
    );
};

export default Page;

const ContentsPaper = styled(Paper)(({ theme }) => ({
    marginBlock: theme.spacing(2),
    padding: theme.spacing(5, 3),
    [theme.breakpoints.up("sm")]: { padding: theme.spacing(5) },
    // This width fits the QR code secret in one line under default settings.
    width: "min(440px, 85vw)",
    minHeight: "375px",
    display: "flex",
    flexDirection: "column",
    gap: theme.spacing(4),
    boxShadow: "none",
    borderRadius: "20px",
}));

interface InstructionsProps {
    twoFactorSecret: TwoFactorSecret | undefined;
}

const Instructions: React.FC<InstructionsProps> = ({ twoFactorSecret }) => {
    const [setupMode, setSetupMode] = useState<"qr" | "manual">("qr");

    return (
        <Stack sx={{ gap: 3, alignItems: "center" }}>
            {setupMode == "qr" ? (
                <SetupQRMode
                    twoFactorSecret={twoFactorSecret}
                    onChangeMode={() => setSetupMode("manual")}
                />
            ) : (
                <SetupManualMode
                    twoFactorSecret={twoFactorSecret}
                    onChangeMode={() => setSetupMode("qr")}
                />
            )}
        </Stack>
    );
};

interface SetupManualModeProps {
    twoFactorSecret: TwoFactorSecret | undefined;
    onChangeMode: () => void;
}

const SetupManualMode: React.FC<SetupManualModeProps> = ({
    twoFactorSecret,
    onChangeMode,
}) => (
    <>
        <Typography sx={{ color: "text.muted", textAlign: "center", px: 2 }}>
            {t("two_factor_manual_entry_message")}
        </Typography>
        <CodeBlock code={twoFactorSecret?.secretCode} />
        <LinkButton onClick={onChangeMode}>{t("scan_qr_title")}</LinkButton>
    </>
);

interface SetupQRModeProps {
    twoFactorSecret?: TwoFactorSecret;
    onChangeMode: () => void;
}

const SetupQRMode: React.FC<SetupQRModeProps> = ({
    twoFactorSecret,
    onChangeMode,
}) => (
    <>
        <Typography sx={{ color: "text.muted", textAlign: "center" }}>
            {t("two_factor_qr_help")}
        </Typography>
        {twoFactorSecret ? (
            <QRCode src={`data:image/png;base64,${twoFactorSecret.qrCode}`} />
        ) : (
            <LoadingQRCode>
                <ActivityIndicator />
            </LoadingQRCode>
        )}
        <LinkButton onClick={onChangeMode}>
            {t("two_factor_manual_entry_title")}
        </LinkButton>
    </>
);

const QRCode = styled("img")(`
    width: 200px;
    height: 200px;
`);

const LoadingQRCode = styled(Stack)(
    ({ theme }) => `
    width: 200px;
    height: 200px;
    border: 1px solid ${theme.vars.palette.stroke.muted};
    align-items: center;
    justify-content: center;
   `,
);
