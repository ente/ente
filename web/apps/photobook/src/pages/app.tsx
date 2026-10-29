import { useBook } from "@/context/book";
import { usePhotoImport } from "@/hooks/usePhotoImport";
import { Box, CircularProgress } from "@mui/material";
import dynamic from "next/dynamic";
import { useRouter } from "next/router";
import { useEffect } from "react";

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
    const router = useRouter();
    const { book, loading } = useBook();
    const { importActive } = usePhotoImport();
    const emptyBook = !loading && !importActive && book.pages.length === 0;

    useEffect(() => {
        if (emptyBook) void router.replace("/");
    }, [emptyBook, router]);

    return loading || emptyBook ? null : <AppShell />;
}
