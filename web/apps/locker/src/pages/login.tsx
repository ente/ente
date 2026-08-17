import { Paper, Stack, styled } from "@mui/material";
import { LoginContents } from "ente-accounts/components/LoginContents";
import { savedPartialLocalUser } from "ente-accounts/services/accounts-db";
import { CenteredFill } from "ente-base/components/containers";
import { EnteLogo } from "ente-base/components/EnteLogo";
import { LoadingIndicator } from "ente-base/components/loaders";
import { NavbarBase } from "ente-base/components/Navbar";
import { customAPIHost } from "ente-base/origins";
import { useRouter } from "next/router";
import React, { useCallback, useEffect, useState } from "react";

const AccountsPagePaper = styled(Paper)(({ theme }) => ({
    marginBlock: theme.spacing(2),
    padding: theme.spacing(5, 3),
    [theme.breakpoints.up("sm")]: { padding: theme.spacing(5) },
    width: "min(420px, 85vw)",
    minHeight: "375px",
    display: "flex",
    flexDirection: "column",
    gap: theme.spacing(4),
    boxShadow: "none",
    borderRadius: "20px",
}));

const Page: React.FC = () => {
    const [loading, setLoading] = useState(true);
    const [host, setHost] = useState<string | undefined>(undefined);

    const router = useRouter();

    const refreshHost = useCallback(
        () => void customAPIHost().then(setHost),
        [],
    );

    useEffect(() => {
        refreshHost();
        if (savedPartialLocalUser()?.email) {
            void router.replace("/verify");
            return;
        }
        setLoading(false);
    }, [router, refreshHost]);

    const onSignUp = useCallback(() => void router.push("/signup"), [router]);

    return loading ? (
        <LoadingIndicator />
    ) : (
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
            <CenteredFill
                sx={[
                    { bgcolor: "secondary.main" },
                    (theme) =>
                        theme.applyStyles("dark", {
                            bgcolor: "background.default",
                        }),
                ]}
            >
                <AccountsPagePaper>
                    <LoginContents {...{ host, onSignUp }} />
                </AccountsPagePaper>
            </CenteredFill>
        </Stack>
    );
};

export default Page;
