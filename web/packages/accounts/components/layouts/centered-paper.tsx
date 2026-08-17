import { Paper, Stack, styled, Typography } from "@mui/material";
import { CenteredFill } from "ente-base/components/containers";
import { EnteLogo } from "ente-base/components/EnteLogo";
import { NavbarBase } from "ente-base/components/Navbar";

export const AccountsPageContents: React.FC<React.PropsWithChildren> = ({
    children,
}) => (
    <Stack
        sx={[
            { minHeight: "100svh", bgcolor: "secondary.main" },
            (theme) =>
                theme.applyStyles("dark", { bgcolor: "background.default" }),
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
            <AccountsPagePaper>{children}</AccountsPagePaper>
        </CenteredFill>
    </Stack>
);

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

export const AccountsPageTitle: React.FC<React.PropsWithChildren> = ({
    children,
}) => (
    <Typography variant="h3" sx={{ flex: 1 }}>
        {children}
    </Typography>
);

export const AccountsPageFooter: React.FC<React.PropsWithChildren> = ({
    children,
}) => (
    <Stack
        direction="row"
        sx={{
            mx: "4px",
            justifyContent: "space-between",
            "& :only-child": { marginInline: "auto" },
        }}
    >
        {children}
    </Stack>
);
