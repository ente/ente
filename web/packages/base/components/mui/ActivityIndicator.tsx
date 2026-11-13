import {
    CircularProgress,
    Stack,
    Typography,
    type CircularProgressProps,
} from "@mui/material";
import type React from "react";

export const ActivityIndicator: React.FC<
    React.PropsWithChildren<CircularProgressProps>
> = ({ children, ...rest }) =>
    children ? (
        <Stack sx={{ gap: 2, alignItems: "center" }}>
            <CircularProgress color="accent" size={24} {...rest} />
            <Typography sx={{ color: "text.muted" }}>{children}</Typography>
        </Stack>
    ) : (
        <CircularProgress color="accent" size={32} {...rest} />
    );
