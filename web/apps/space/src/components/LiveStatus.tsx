import { Box } from "@mui/material";
import { visuallyHidden } from "@mui/utils";
import type React from "react";

export const SpaceLiveStatus: React.FC<React.PropsWithChildren> = ({
    children,
}) => (
    <Box role="status" aria-atomic="true" sx={visuallyHidden}>
        {children}
    </Box>
);
