import { Paper, Stack, Typography } from "@mui/material";
import { CenteredFill } from "ente-base/components/containers";
import { EnteLogo } from "ente-base/components/EnteLogo";
import { NavbarBase } from "ente-base/components/Navbar";
import {
    singleInputPagePaperSx,
    v2TitleSx,
} from "ente-base/components/SingleInput.styles";

export const PublicAccessLayout: React.FC<React.PropsWithChildren> = ({
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
            <Paper sx={singleInputPagePaperSx}>{children}</Paper>
        </CenteredFill>
    </Stack>
);

export const PublicAccessLayoutTitle: React.FC<React.PropsWithChildren> = ({
    children,
}) => <Typography sx={v2TitleSx}>{children}</Typography>;
