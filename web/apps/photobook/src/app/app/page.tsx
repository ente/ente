"use client";

import { Box, CircularProgress } from "@mui/material";
import dynamic from "next/dynamic";

// Dynamic import the entire app to avoid SSR issues with Konva/canvas
const AppShell = dynamic(() => import("@/components/AppShell"), {
    ssr: false,
    loading: () => (
        <Box
            sx={{
                minHeight: "100vh",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
            }}
        >
            <CircularProgress sx={{ color: "#08C225" }} />
        </Box>
    ),
});

export default function Home() {
    return <AppShell />;
}
